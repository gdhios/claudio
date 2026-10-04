/**
 * The Face key: Claudio's mascot, spread across the fifteen keys of a deck.
 *
 * Fifteen keys, one board: each key says which of the fifteen windows it draws when it
 * appears, and only the tiles a change actually touches are ever redrawn. Two decks never
 * share a board, even when their keys sit at the same coordinates — each has its own idea
 * of what it is showing.
 */

import {
	type DidReceiveSettingsEvent,
	type KeyDownEvent,
	SingletonAction,
	type WillAppearEvent,
	type WillDisappearEvent,
} from "@elgato/streamdeck";

import { readIdleSeconds } from "../idle.js";
import { changedTiles, type FaceParams, faceSvg, tileKey, tileSvg } from "../render/face.js";
import { faceLook, mayBlink } from "../render/look.js";
import type { StoreSnapshot } from "../state/store.js";
import { Blink } from "./blink.js";
import { type KeyDependencies, KeyPainter, type PaintableKey } from "./keys.js";

/** Identifier of this action in the manifest. */
export const FACE_UUID = "com.okonoma.claudio.face";

/** Where the message written across the middle tile lives in the translation files. */
export const FACE_MESSAGE_KEY = "face.disconnected.message";

/** How often the moustache may catch up with the voice: fast enough to read as alive. */
export const LEVEL_COALESCE_MS = 167;

export type FaceKeySettings = {
	/** How long the deck may sit on a working page; a select's value, so it arrives as text. */
	idleSeconds?: string | number;
};

export type FaceDependencies = KeyDependencies & {
	/** Listens to the microphone level while a dictation runs. */
	onLevel: (listener: (value: number) => void) => () => void;

	/** Takes a deck to the actions page, and arms its way back to the face. */
	showActions: (deviceId: string) => Promise<void>;

	/** Records that a deck is already home, so nothing tries to bring it back there. */
	sawFace: (deviceId: string) => void;

	/** Sets how long a deck may be left on a working page before it comes home on its own. */
	setIdleSeconds: (seconds: number) => void;
};

/** One tile of a board: where it sits, and the key it is drawn on. */
type Tile = { column: number; row: number; action: PaintableKey };

/**
 * The fifteen tiles of one deck, and the face they last showed.
 *
 * A board only ever redraws what {@link changedTiles} says moved: the same rule the
 * fifteen keys share is what lets a blink cost two drawings instead of fifteen.
 */
class FaceBoard {
	readonly #tiles = new Map<string, Tile>();
	#shown: FaceParams | null = null;

	/**
	 * Registers a tile that just appeared, and draws it with what the board already shows.
	 * @param action Key to draw on.
	 * @param column Column it sits on.
	 * @param row Row it sits on.
	 * @param params What the board is showing right now.
	 * @param painter Where the drawing goes.
	 */
	public async attach(action: PaintableKey, column: number, row: number, params: FaceParams, painter: KeyPainter): Promise<void> {
		this.#tiles.set(action.id, { column, row, action });
		this.#shown = params;
		await painter.paint(action, tileSvg(faceSvg(params), column, row));
	}

	/**
	 * Forgets a tile that left the page.
	 * @param action The key.
	 * @param painter Where the drawing was going.
	 */
	public detach(action: { readonly id: string }, painter: KeyPainter): void {
		this.#tiles.delete(action.id);
		painter.forget(action);
	}

	/**
	 * Redraws whatever changed since the last drawing, across every tile still on screen.
	 * @param params What the board should show now.
	 * @param painter Where the drawings go.
	 */
	public async redraw(params: FaceParams, painter: KeyPainter): Promise<void> {
		const changed = this.#shown === null ? null : changedTiles(this.#shown, params);
		this.#shown = params;
		if (changed !== null && changed.size === 0) {
			return;
		}

		const svg = faceSvg(params);
		for (const { column, row, action } of this.#tiles.values()) {
			if (changed !== null && !changed.has(tileKey(column, row))) {
				continue;
			}

			await painter.paint(action, tileSvg(svg, column, row));
		}
	}
}

export class FaceKey extends SingletonAction<FaceKeySettings> {
	public override readonly manifestId = FACE_UUID;

	readonly #deps: FaceDependencies;
	readonly #painter = new KeyPainter();
	readonly #boards = new Map<string, FaceBoard>();
	readonly #blink: Blink;

	/** The loudest thing heard since the last frame drawn, oldest kept once the window opens. */
	#level = 0;
	#levelWindow: ReturnType<typeof setTimeout> | null = null;
	#levelPending = false;

	public constructor(deps: FaceDependencies) {
		super();
		this.#deps = deps;
		this.#blink = new Blink(() => void this.#redrawAll(), deps.random);
		deps.store.onChange((snapshot) => void this.#changed(snapshot));
		deps.onLevel((value) => this.#heard(value));
	}

	public override async onWillAppear(ev: WillAppearEvent<FaceKeySettings>): Promise<void> {
		const deviceId = ev.action.device.id;
		this.#deps.setIdleSeconds(readIdleSeconds(ev.payload.settings.idleSeconds));
		this.#deps.sawFace(deviceId);
		// Multi-actions carry no coordinates; the manifest keeps this action out of them.
		const coordinates = "coordinates" in ev.payload ? ev.payload.coordinates : undefined;
		if (!ev.action.isKey() || coordinates === undefined) {
			return;
		}

		const { column, row } = coordinates;
		await this.#boardOf(deviceId).attach(ev.action, column, row, this.#params(), this.#painter);
	}

	public override onWillDisappear(ev: WillDisappearEvent<FaceKeySettings>): void {
		this.#boardOf(ev.action.device.id).detach(ev.action, this.#painter);
	}

	public override onDidReceiveSettings(ev: DidReceiveSettingsEvent<FaceKeySettings>): void {
		const seconds = readIdleSeconds(ev.payload.settings.idleSeconds);
		this.#deps.setIdleSeconds(seconds);
		for (const action of this.actions) {
			if (action.id !== ev.action.id) {
				void action.setSettings({ idleSeconds: seconds });
			}
		}
	}

	public override async onKeyDown(ev: KeyDownEvent<FaceKeySettings>): Promise<void> {
		const deviceId = ev.action.device.id;
		this.#deps.touch(deviceId);
		if (!this.#deps.store.snapshot.connected) {
			await ev.action.showAlert();
			await this.#deps.openClaudio();

			return;
		}

		await this.#deps.showActions(deviceId);
	}

	/** Stops the blinking and the level window, for when the plugin is done with this action. */
	public stop(): void {
		this.#blink.stop();
		if (this.#levelWindow !== null) {
			clearTimeout(this.#levelWindow);
			this.#levelWindow = null;
		}
	}

	/**
	 * Follows the app, and redraws.
	 * @param snapshot What the board draws from.
	 */
	async #changed(snapshot: StoreSnapshot): Promise<void> {
		this.#blink.follow(mayBlink(snapshot));
		await this.#redrawAll();
	}

	/**
	 * Takes in a level from the app, redrawing at once unless a window is already open.
	 * @param value The level, between zero and one.
	 */
	#heard(value: number): void {
		this.#level = value;
		if (this.#levelWindow !== null) {
			this.#levelPending = true;

			return;
		}

		this.#openLevelWindow();
		void this.#redrawAll();
	}

	/** Holds the moustache still for a moment, then draws whatever arrived meanwhile — once. */
	#openLevelWindow(): void {
		this.#levelWindow = setTimeout(() => {
			this.#levelWindow = null;
			if (!this.#levelPending) {
				return;
			}

			this.#levelPending = false;
			this.#openLevelWindow();
			void this.#redrawAll();
		}, LEVEL_COALESCE_MS);
	}

	/**
	 * The board for one device, creating it the first time it is asked for.
	 * @param deviceId The deck.
	 * @returns Its board.
	 */
	#boardOf(deviceId: string): FaceBoard {
		let board = this.#boards.get(deviceId);
		if (board === undefined) {
			board = new FaceBoard();
			this.#boards.set(deviceId, board);
		}

		return board;
	}

	/**
	 * What the face should show right now.
	 * @returns The parameters.
	 */
	#params(): FaceParams {
		const snapshot = this.#deps.store.snapshot;

		return faceLook({
			state: snapshot.state,
			connected: snapshot.connected,
			eyesClosed: this.#blink.closed,
			level: this.#level,
			message: this.#deps.translate(FACE_MESSAGE_KEY),
		});
	}

	/** Redraws every board with what the face shows right now. */
	async #redrawAll(): Promise<void> {
		const params = this.#params();
		for (const board of this.#boards.values()) {
			await board.redraw(params, this.#painter);
		}
	}
}
