import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
	BridgeClient,
	type BridgeSocket,
	type Handshake,
	handshakePath,
	parseHandshake,
	RECONNECT_DELAYS,
	type SocketHandlers,
} from "../src/bridge/client.js";
import type { BridgeState } from "../src/bridge/protocol.js";

const idle: BridgeState = { gaze: "repos", activity: "idle", phase: null, label: null, locked: false };

/** A socket the test drives by hand, standing in for the one `ws` would open. */
class FakeSocket implements BridgeSocket {
	public readonly sent: string[] = [];
	public closed = false;

	public constructor(
		public readonly url: string,
		public readonly handlers: SocketHandlers,
	) {}

	public send(text: string): void {
		this.sent.push(text);
	}

	public close(): void {
		this.closed = true;
		this.handlers.onClose();
	}

	/** Plays the app accepting the handshake. */
	public welcome(state: BridgeState = idle): void {
		this.handlers.onText(JSON.stringify({ type: "welcome", v: 1, app: "1.13.0", state }));
	}
}

/** Everything a client needs, with the file and the socket under the test's control. */
function harness(handshake: Handshake | null = { v: 1, port: 51234, token: "a".repeat(64), pid: 42 }) {
	const sockets: FakeSocket[] = [];
	let current = handshake;

	const client = new BridgeClient({
		pluginVersion: "0.1.0.0",
		readHandshake: () => current,
		createSocket: (url, handlers) => {
			const socket = new FakeSocket(url, handlers);
			sockets.push(socket);
			return socket;
		},
	});

	return {
		client,
		sockets,
		get last(): FakeSocket {
			return sockets[sockets.length - 1]!;
		},
		setHandshake(next: Handshake | null): void {
			current = next;
		},
	};
}

describe("BridgeClient", () => {
	beforeEach(() => {
		vi.useFakeTimers();
	});

	afterEach(() => {
		vi.useRealTimers();
	});

	it("looks for the handshake file where the app writes it", () => {
		expect(handshakePath("/Users/someone")).toBe(
			"/Users/someone/Library/Application Support/Claudio/streamdeck-bridge.json",
		);
	});

	it("dials the loopback port from the handshake file", () => {
		const { client, last } = harnessStarted();

		expect(last.url).toBe("ws://127.0.0.1:51234");
		client.stop();
	});

	it("sends hello as its very first frame", () => {
		const { last } = harnessStarted();

		expect(JSON.parse(last.sent[0]!)).toEqual({
			type: "hello",
			v: 1,
			token: "a".repeat(64),
			plugin: "0.1.0.0",
		});
	});

	it("announces the connection with the state the welcome carries", () => {
		const { client, last } = harnessStarted();
		const connected = vi.fn();
		const states = vi.fn();
		client.on("connected", connected);
		client.on("state", states);

		last.welcome({ ...idle, activity: "dictation", phase: "listening" });

		expect(connected).toHaveBeenCalledOnce();
		expect(states).toHaveBeenLastCalledWith({ ...idle, activity: "dictation", phase: "listening" });
	});

	it("passes on the state and level frames that follow", () => {
		const { client, last } = harnessStarted();
		const states = vi.fn();
		const levels = vi.fn();
		client.on("state", states);
		client.on("level", levels);
		last.welcome();

		last.handlers.onText('{"type":"state","gaze":"veille","activity":"correction","phase":"streaming","label":null,"locked":false}');
		last.handlers.onText('{"type":"level","value":0.42}');

		expect(states).toHaveBeenLastCalledWith({
			gaze: "veille",
			activity: "correction",
			phase: "streaming",
			label: null,
			locked: false,
		});
		expect(levels).toHaveBeenCalledWith(0.42);
	});

	it("shrugs off a frame it cannot read", () => {
		const { last } = harnessStarted();
		last.welcome();

		expect(() => last.handlers.onText("{ not json")).not.toThrow();
	});

	it("sends what it is asked to, once the app has said welcome", () => {
		const { client, last } = harnessStarted();
		last.welcome();

		expect(client.send({ type: "action", id: "correct" })).toBe(true);
		expect(JSON.parse(last.sent[1]!)).toEqual({ type: "action", id: "correct" });
	});

	it("sends nothing before the app has said welcome", () => {
		const { client, last } = harnessStarted();

		expect(client.send({ type: "action", id: "correct" })).toBe(false);
		expect(last.sent).toHaveLength(1);
	});

	it("reports a connection that drops", () => {
		const { client, last } = harnessStarted();
		const disconnected = vi.fn();
		client.on("disconnected", disconnected);
		last.welcome();

		last.handlers.onClose();

		expect(disconnected).toHaveBeenCalledOnce();
		expect(client.send({ type: "action", id: "correct" })).toBe(false);
	});

	it("backs off one, two, four then ten seconds, and stays there", () => {
		expect(RECONNECT_DELAYS).toEqual([1000, 2000, 4000, 10000]);
		const { client, sockets, last } = harnessStarted();
		last.handlers.onClose();

		for (const delay of [1000, 2000, 4000, 10000, 10000]) {
			const before = sockets.length;
			vi.advanceTimersByTime(delay - 1);
			expect(sockets).toHaveLength(before);

			vi.advanceTimersByTime(1);
			expect(sockets).toHaveLength(before + 1);
			sockets[sockets.length - 1]!.handlers.onClose();
		}

		client.stop();
	});

	it("starts counting again after a welcome", () => {
		const { client, sockets, last } = harnessStarted();
		last.handlers.onClose();
		vi.advanceTimersByTime(1000);
		sockets[1]!.handlers.onClose();
		vi.advanceTimersByTime(2000);

		sockets[2]!.welcome();
		sockets[2]!.handlers.onClose();
		vi.advanceTimersByTime(1000);

		expect(sockets).toHaveLength(4);
		client.stop();
	});

	it("re-reads the handshake file on every attempt", () => {
		const { client, sockets, last, setHandshake } = harnessStarted();
		last.handlers.onClose();
		setHandshake({ v: 1, port: 60001, token: "b".repeat(64), pid: 43 });

		vi.advanceTimersByTime(1000);
		sockets[1]!.handlers.onOpen();

		expect(sockets[1]!.url).toBe("ws://127.0.0.1:60001");
		expect(JSON.parse(sockets[1]!.sent[0]!)).toMatchObject({ token: "b".repeat(64) });
		client.stop();
	});

	it("waits and looks again when the handshake file is not there", () => {
		const { client, sockets, setHandshake } = harness(null);
		client.start();

		expect(sockets).toHaveLength(0);

		setHandshake({ v: 1, port: 51234, token: "a".repeat(64), pid: 42 });
		vi.advanceTimersByTime(1000);

		expect(sockets).toHaveLength(1);
		client.stop();
	});

	it("keeps trying when opening the socket throws outright", () => {
		// An unusable port makes `new WebSocket(…)` throw where nothing would catch it,
		// and the plugin would then sit there with no attempt pending.
		const sockets: FakeSocket[] = [];
		let explode = true;
		const client = new BridgeClient({
			pluginVersion: "0.1.0.0",
			readHandshake: () => ({ v: 1, port: 51234, token: "a".repeat(64), pid: 42 }),
			createSocket: (url, handlers) => {
				if (explode) {
					explode = false;
					throw new Error("Port should be > 0 and < 65536");
				}

				const socket = new FakeSocket(url, handlers);
				sockets.push(socket);

				return socket;
			},
		});

		client.start();
		expect(sockets).toHaveLength(0);

		vi.advanceTimersByTime(1000);

		expect(sockets).toHaveLength(1);
		client.stop();
	});

	it("refuses a handshake file written for another protocol version", () => {
		const { client, sockets } = harness({ v: 2, port: 51234, token: "a".repeat(64), pid: 42 });
		client.start();

		expect(sockets).toHaveLength(0);
		client.stop();
	});

	it("stops trying while Claudio is not running", () => {
		const { client, sockets, last } = harnessStarted();
		client.setClaudioRunning(false);

		expect(last.closed).toBe(true);
		vi.advanceTimersByTime(60_000);

		expect(sockets).toHaveLength(1);
		client.stop();
	});

	it("dials again the moment Claudio comes back", () => {
		const { client, sockets } = harnessStarted();
		client.setClaudioRunning(false);

		client.setClaudioRunning(true);

		expect(sockets).toHaveLength(2);
		client.stop();
	});

	it("gives up entirely when it is stopped", () => {
		const { client, sockets, last } = harnessStarted();

		client.stop();
		last.handlers.onClose();
		vi.advanceTimersByTime(60_000);

		expect(sockets).toHaveLength(1);
	});
});

/**
 * A started client whose first socket is open.
 */
function harnessStarted(): ReturnType<typeof harness> {
	const h = harness();
	h.client.start();
	h.last.handlers.onOpen();

	return h;
}

describe("parseHandshake", () => {
	const complete = { v: 1, port: 51234, token: "a".repeat(64), pid: 42 };

	it("reads the file the app writes", () => {
		expect(parseHandshake(JSON.stringify(complete))).toEqual(complete);
	});

	it.each([
		["not JSON at all", "{ not json"],
		["a file that is not an object", '"51234"'],
		["a missing port", JSON.stringify({ ...complete, port: undefined })],
		["a port of zero", JSON.stringify({ ...complete, port: 0 })],
		["a negative port", JSON.stringify({ ...complete, port: -1 })],
		["a port above the range", JSON.stringify({ ...complete, port: 70000 })],
		["a port that is not whole", JSON.stringify({ ...complete, port: 1.5 })],
		["a token that is not a string", JSON.stringify({ ...complete, token: 1234 })],
		["a missing version", JSON.stringify({ ...complete, v: undefined })],
	])("refuses %s", (_why, contents) => {
		expect(parseHandshake(contents)).toBeNull();
	});

	it("accepts the highest port there is", () => {
		expect(parseHandshake(JSON.stringify({ ...complete, port: 65535 }))).not.toBeNull();
	});
});
