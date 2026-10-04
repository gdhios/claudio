/**
 * The connection to Claudio.
 *
 * The app writes a handshake file with the loopback port and a one-shot token, then
 * listens there; it removes the file when it quits or when the bridge is switched off.
 * So the file is re-read on every attempt: a port from the last run is worth nothing.
 */

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import WebSocket from "ws";

import {
	type BridgeInbound,
	type BridgeState,
	parseOutbound,
	PROTOCOL_VERSION,
	serializeInbound,
} from "./protocol.js";

/** What the app writes so the plugin can find it. */
export type Handshake = {
	v: number;
	port: number;
	token: string;
	pid: number;
};

/** How long to wait before each further attempt; the last one repeats forever. */
export const RECONNECT_DELAYS = [1000, 2000, 4000, 10000] as const;

/** The bridge speaks in text frames, and refuses anything larger. */
const MAX_FRAME_BYTES = 64 * 1024;

/** What the client does with what a socket tells it. */
export type SocketHandlers = {
	onOpen(): void;
	onText(text: string): void;
	onClose(): void;
	onError(error: Error): void;
};

/** The little a socket has to do for the client. */
export type BridgeSocket = {
	send(text: string): void;
	close(): void;
};

export type SocketFactory = (url: string, handlers: SocketHandlers) => BridgeSocket;

/** Somewhere to say what went wrong; Stream Deck's own logger fits. */
export type BridgeLogger = {
	error(message: string, error?: unknown): void;
};

export type BridgeEvents = {
	/** The app accepted the handshake; carries the state it sent with it. */
	connected: (state: BridgeState) => void;

	/** An established connection dropped. */
	disconnected: () => void;

	/** The app's state changed. */
	state: (state: BridgeState) => void;

	/** The microphone level, while a dictation is listening. */
	level: (value: number) => void;
};

export type BridgeClientOptions = {
	/** Version this plugin announces in its `hello`. */
	pluginVersion: string;

	/** Reads the handshake file; the real one by default. */
	readHandshake?: () => Handshake | null;

	/** Opens a socket; a bundled `ws` one by default. */
	createSocket?: SocketFactory;

	/** Where to report what went wrong; silence by default. */
	logger?: BridgeLogger;
};

/**
 * Where the app drops the port and the token.
 * @param home The user's home directory.
 * @returns The path of the handshake file.
 */
export function handshakePath(home: string = homedir()): string {
	return path.join(home, "Library", "Application Support", "Claudio", "streamdeck-bridge.json");
}

/**
 * Reads the handshake file, or `null` when it is missing or unreadable.
 * @param file Path of the handshake file.
 * @returns The handshake.
 */
export function readHandshake(file: string = handshakePath()): Handshake | null {
	try {
		return parseHandshake(readFileSync(file, "utf8"));
	} catch {
		return null;
	}
}

/**
 * Reads the contents of a handshake file, or `null` when they are not usable.
 *
 * The port has to be a whole number inside the TCP range: anything else and the socket
 * constructor throws rather than fails, which would end the attempts instead of delaying
 * them.
 * @param contents Contents of the handshake file.
 * @returns The handshake.
 */
export function parseHandshake(contents: string): Handshake | null {
	let parsed: unknown;
	try {
		parsed = JSON.parse(contents);
	} catch {
		return null;
	}

	if (typeof parsed !== "object" || parsed === null) {
		return null;
	}

	const { v, port, token, pid } = parsed as Partial<Handshake>;
	if (
		typeof v !== "number" ||
		typeof token !== "string" ||
		typeof pid !== "number" ||
		!isPort(port)
	) {
		return null;
	}

	return { v, port, token, pid };
}

/**
 * Tells whether a value is a port a socket can actually be opened on.
 * @param value Value to check.
 * @returns `true` when it is.
 */
function isPort(value: unknown): value is number {
	return typeof value === "number" && Number.isInteger(value) && value > 0 && value < 65536;
}

export class BridgeClient {
	readonly #options: Required<Pick<BridgeClientOptions, "pluginVersion">> & {
		readHandshake: () => Handshake | null;
		createSocket: SocketFactory;
		logger: BridgeLogger;
	};

	readonly #listeners: { [K in keyof BridgeEvents]: Set<BridgeEvents[K]> } = {
		connected: new Set(),
		disconnected: new Set(),
		state: new Set(),
		level: new Set(),
	};

	#running = false;
	#claudioRunning = true;
	#connected = false;
	#attempt = 0;
	#socket: BridgeSocket | null = null;
	#retry: ReturnType<typeof setTimeout> | null = null;

	public constructor(options: BridgeClientOptions) {
		this.#options = {
			pluginVersion: options.pluginVersion,
			readHandshake: options.readHandshake ?? ((): Handshake | null => readHandshake()),
			createSocket: options.createSocket ?? nodeSocket,
			logger: options.logger ?? { error: (): void => {} },
		};
	}

	/**
	 * Listens for an event.
	 * @param event Event to listen for.
	 * @param listener Function called when it happens.
	 * @returns A function that stops the listening.
	 */
	public on<K extends keyof BridgeEvents>(event: K, listener: BridgeEvents[K]): () => void {
		this.#listeners[event].add(listener as never);

		return () => this.#listeners[event].delete(listener as never);
	}

	/** Starts dialling, and keeps dialling until {@link BridgeClient.stop}. */
	public start(): void {
		if (this.#running) {
			return;
		}

		this.#running = true;
		this.#attempt = 0;
		this.#connect();
	}

	/** Hangs up for good. */
	public stop(): void {
		this.#running = false;
		this.#cancelRetry();
		this.#drop();
	}

	/**
	 * Tells the client whether Claudio is running; it does not dial an app that is not there.
	 * @param running Whether Claudio is running.
	 */
	public setClaudioRunning(running: boolean): void {
		if (this.#claudioRunning === running) {
			return;
		}

		this.#claudioRunning = running;
		if (!running) {
			this.#cancelRetry();
			this.#drop();
			return;
		}

		this.#attempt = 0;
		this.#connect();
	}

	/**
	 * Sends a frame to the app.
	 * @param message Frame to send.
	 * @returns `true` when it went out; `false` when there was nobody to send it to.
	 */
	public send(message: BridgeInbound): boolean {
		if (!this.#connected || this.#socket === null) {
			return false;
		}

		try {
			this.#socket.send(serializeInbound(message));
			return true;
		} catch (error) {
			this.#options.logger.error("Failed to send a frame to Claudio", error);
			return false;
		}
	}

	/** Reads the handshake file and opens a socket, or schedules another attempt. */
	#connect(): void {
		if (!this.#running || !this.#claudioRunning || this.#socket !== null) {
			return;
		}

		const handshake = this.#options.readHandshake();
		if (handshake === null) {
			this.#scheduleRetry();
			return;
		}

		if (handshake.v !== PROTOCOL_VERSION) {
			this.#options.logger.error(`Claudio speaks protocol version ${handshake.v}, this plugin speaks ${PROTOCOL_VERSION}`);
			this.#scheduleRetry();
			return;
		}

		try {
			this.#socket = this.#options.createSocket(`ws://127.0.0.1:${handshake.port}`, {
				onOpen: () => this.#hello(handshake.token),
				onText: (text) => this.#receive(text),
				onClose: () => this.#closed(),
				onError: (error) => this.#options.logger.error("The bridge connection failed", error),
			});
		} catch (error) {
			// Opening a socket can throw rather than fail, and this runs inside a timer
			// callback where nothing would catch it: without this the attempts would stop.
			this.#socket = null;
			this.#options.logger.error("Could not open a connection to Claudio", error);
			this.#scheduleRetry();
		}
	}

	/**
	 * Introduces the plugin; the app closes the connection if this is not the first frame.
	 * @param token Token from the handshake file.
	 */
	#hello(token: string): void {
		this.#socket?.send(
			serializeInbound({
				type: "hello",
				v: PROTOCOL_VERSION,
				token,
				plugin: this.#options.pluginVersion,
			}),
		);
	}

	/**
	 * Handles a frame from the app.
	 * @param text The text frame.
	 */
	#receive(text: string): void {
		let frame;
		try {
			frame = parseOutbound(text);
		} catch (error) {
			this.#options.logger.error("Claudio sent a frame this plugin cannot read", error);
			return;
		}

		switch (frame.type) {
			case "welcome":
				this.#attempt = 0;
				this.#connected = true;
				this.#emit("connected", frame.state);
				this.#emit("state", frame.state);
				break;
			case "state": {
				const { type: _type, ...state } = frame;
				this.#emit("state", state);
				break;
			}
			case "level":
				this.#emit("level", frame.value);
				break;
			case "error":
				this.#options.logger.error(`Claudio refused the connection (${frame.code}): ${frame.message}`);
				this.#drop();
				break;
			case "bye":
				this.#drop();
				break;
		}
	}

	/** Handles a socket that closed, whoever closed it. */
	#closed(): void {
		const wasConnected = this.#connected;
		this.#connected = false;
		this.#socket = null;

		if (wasConnected) {
			this.#emit("disconnected");
		}

		this.#scheduleRetry();
	}

	/** Closes the socket, if there is one. */
	#drop(): void {
		const socket = this.#socket;
		if (socket === null) {
			return;
		}

		try {
			socket.close();
		} catch (error) {
			this.#options.logger.error("Failed to close the bridge connection", error);
		}
	}

	/** Waits, then tries again — a little longer each time, up to ten seconds. */
	#scheduleRetry(): void {
		if (!this.#running || !this.#claudioRunning || this.#retry !== null) {
			return;
		}

		const delay = RECONNECT_DELAYS[Math.min(this.#attempt, RECONNECT_DELAYS.length - 1)]!;
		this.#attempt += 1;
		this.#retry = setTimeout(() => {
			this.#retry = null;
			this.#connect();
		}, delay);
	}

	/** Forgets a pending attempt. */
	#cancelRetry(): void {
		if (this.#retry !== null) {
			clearTimeout(this.#retry);
			this.#retry = null;
		}
	}

	/**
	 * Tells the listeners of an event.
	 * @param event Event that happened.
	 * @param args What to tell them.
	 */
	#emit<K extends keyof BridgeEvents>(event: K, ...args: Parameters<BridgeEvents[K]>): void {
		for (const listener of [...this.#listeners[event]]) {
			(listener as (...a: Parameters<BridgeEvents[K]>) => void)(...args);
		}
	}
}

/**
 * Opens a real socket. `ws` is bundled in because the Node 20 runtime Stream Deck ships
 * has no global WebSocket.
 * @param url Address of the bridge.
 * @param handlers What to do with what it says.
 * @returns The socket.
 */
function nodeSocket(url: string, handlers: SocketHandlers): BridgeSocket {
	const socket = new WebSocket(url, { maxPayload: MAX_FRAME_BYTES });

	socket.on("open", () => handlers.onOpen());
	socket.on("message", (data) => handlers.onText(data.toString()));
	socket.on("close", () => handlers.onClose());
	socket.on("error", (error) => handlers.onError(error));

	return {
		send: (text) => socket.send(text),
		close: () => socket.close(),
	};
}
