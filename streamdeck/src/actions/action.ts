/**
 * The Action key: one of Claudio's actions, run on whatever is selected.
 */

import {
	type DidReceiveSettingsEvent,
	type KeyDownEvent,
	SingletonAction,
	type WillAppearEvent,
	type WillDisappearEvent,
} from "@elgato/streamdeck";

import type { ClaudioActionId } from "../bridge/protocol.js";
import {
	chevron,
	doubleChevron,
	grid,
	mascot,
	meltingLines,
	musicNote,
	textCorrect,
	tie,
	word,
} from "../render/glyphs.js";
import { keySvg } from "../render/key.js";
import type { StoreSnapshot } from "../state/store.js";
import { type KeyDependencies, KeyPainter, type PaintableKey } from "./keys.js";

/** Identifier of this action in the manifest. */
export const ACTION_UUID = "com.okonoma.claudio.action";

/** What a fresh key does. */
export const DEFAULT_ACTION_ID: ClaudioActionId = "correct";

export type ActionKeySettings = {
	id?: ClaudioActionId;
};

/** The drawing that stands for each action. */
const GLYPHS: Record<ClaudioActionId, () => string> = {
	correct: textCorrect,
	makePrompt: chevron,
	expertPrompt: doubleChevron,
	translateFR: () => word("FR"),
	translateEN: () => word("EN"),
	professionalTone: tie,
	summarize: meltingLines,
	// He reads it back to you in plain words, and he is pleased with himself for it.
	simplify: () => mascot("repos"),
	free: () => mascot("fait"),
	palette: grid,
	whatsPlaying: musicNote,
};

/**
 * The actions that start no correction. "What's playing?" opens a panel of its own, and
 * the app closes whatever correction was in flight to make room for it.
 */
const STARTS_NO_CORRECTION: ReadonlySet<ClaudioActionId> = new Set(["whatsPlaying"]);

/**
 * Where the label of an action lives in the translation files.
 * @param id The action.
 * @returns The translation key.
 */
export function labelKey(id: ClaudioActionId): string {
	return `action.${id}.label`;
}

export class ClaudioActionKey extends SingletonAction<ActionKeySettings> {
	public override readonly manifestId = ACTION_UUID;

	readonly #deps: KeyDependencies;
	readonly #painter = new KeyPainter();
	readonly #settings = new Map<string, ActionKeySettings>();

	/**
	 * The phase of the correction, and only of the correction: a dictation runs its own
	 * course and reaches its own `done`, which must not be mistaken for this one.
	 */
	#correctionPhase: string | null = null;

	/**
	 * The key whose press started the work in flight, if a key did. A correction started
	 * from the keyboard belongs to no key, and ticks none.
	 */
	#pressedKeyId: string | null = null;

	public constructor(deps: KeyDependencies) {
		super();
		this.#deps = deps;
		deps.store.onChange((snapshot) => void this.#redrawAll(snapshot));
	}

	public override async onWillAppear(ev: WillAppearEvent<ActionKeySettings>): Promise<void> {
		this.#settings.set(ev.action.id, ev.payload.settings);
		if (ev.action.isKey()) {
			await this.#draw(ev.action, ev.payload.settings, this.#deps.store.snapshot);
		}
	}

	public override onWillDisappear(ev: WillDisappearEvent<ActionKeySettings>): void {
		this.#settings.delete(ev.action.id);
		this.#painter.forget(ev.action);
		if (this.#pressedKeyId === ev.action.id) {
			// There is no longer a key to tick, and the identifier could come back as another.
			this.#pressedKeyId = null;
		}
	}

	public override async onDidReceiveSettings(ev: DidReceiveSettingsEvent<ActionKeySettings>): Promise<void> {
		this.#settings.set(ev.action.id, ev.payload.settings);
		if (ev.action.isKey()) {
			await this.#draw(ev.action, ev.payload.settings, this.#deps.store.snapshot);
		}
	}

	public override async onKeyDown(ev: KeyDownEvent<ActionKeySettings>): Promise<void> {
		this.#deps.touch(ev.action.device.id);
		if (!this.#deps.store.snapshot.connected) {
			await ev.action.showAlert();
			await this.#deps.openClaudio();
			return;
		}

		const id = ev.payload.settings.id ?? DEFAULT_ACTION_ID;
		// The connection can still go between that check and the write.
		if (!this.#deps.bridge.send({ type: "action", id })) {
			await ev.action.showAlert();
			return;
		}

		// The latest press owns the tick. One that starts no correction leaves no key owed
		// one, its own included: the correction in flight, if any, is gone.
		this.#pressedKeyId = STARTS_NO_CORRECTION.has(id) ? null : ev.action.id;
	}

	/**
	 * Redraws every visible key, and ticks the one whose correction has just landed.
	 * @param snapshot What the keys draw from.
	 */
	async #redrawAll(snapshot: StoreSnapshot): Promise<void> {
		const tickFor = this.#whoseCorrectionLanded(snapshot);

		for (const action of this.actions) {
			if (!action.isKey()) {
				continue;
			}

			await this.#draw(action, this.#settings.get(action.id) ?? {}, snapshot);
			if (action.id === tickFor) {
				await action.showOk();
			}
		}
	}

	/**
	 * Follows the correction from one frame to the next, and names the key to tick when it
	 * lands. Frames belonging to anything else leave the correction where it was.
	 * @param snapshot What the keys draw from.
	 * @returns The key to tick, or `null`.
	 */
	#whoseCorrectionLanded(snapshot: StoreSnapshot): string | null {
		const state = snapshot.state;
		if (state?.activity !== "correction") {
			return null;
		}

		const landed = state.phase === "done" && this.#correctionPhase !== "done";
		this.#correctionPhase = state.phase;
		if (!landed) {
			return null;
		}

		// The tick belongs to the press that asked for it, and to that press only.
		const pressed = this.#pressedKeyId;
		this.#pressedKeyId = null;

		return pressed;
	}

	/**
	 * Draws one key.
	 * @param action Key to draw on.
	 * @param settings What that key carries.
	 * @param snapshot What the keys draw from.
	 */
	async #draw(
		action: PaintableKey,
		settings: ActionKeySettings,
		snapshot: StoreSnapshot,
	): Promise<void> {
		const id = settings.id ?? DEFAULT_ACTION_ID;
		const { state, connected } = snapshot;
		// While a correction streams, every Claudio key becomes the mascot keeping watch.
		const working = state?.activity === "correction" && state.phase === "streaming";

		await this.#painter.paint(
			action,
			keySvg({
				glyph: working ? mascot("veille") : GLYPHS[id](),
				label: this.#deps.translate(labelKey(id)),
				dimmed: !connected,
			}),
		);
	}
}
