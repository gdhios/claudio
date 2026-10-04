/**
 * The Dictate key: hold it to dictate, and watch what Claudio does with what was said.
 *
 * The press is the whole gesture — down starts, up ends, whatever the app is doing in
 * between. Every Dictate key on the page then mirrors the same dictation, because there
 * is only one microphone and one store behind them.
 */

import {
	type DidReceiveSettingsEvent,
	type KeyDownEvent,
	type KeyUpEvent,
	SingletonAction,
	type WillAppearEvent,
	type WillDisappearEvent,
} from "@elgato/streamdeck";

import type { BridgeState, DictationLanguage, DictationOutput } from "../bridge/protocol.js";
import { dictateLook } from "../render/dictate.js";
import { keySvg } from "../render/key.js";
import type { StoreSnapshot } from "../state/store.js";
import { type KeyDependencies, KeyPainter, type PaintableKey } from "./keys.js";
import { LevelMeter } from "./meter.js";

/** Identifier of this action in the manifest. */
export const DICTATE_UUID = "com.okonoma.claudio.dictate";

/** What a fresh key listens in. */
export const DEFAULT_LANGUAGE: DictationLanguage = "primary";

/** What a fresh key does with what it heard. */
export const DEFAULT_OUTPUT: DictationOutput = "cleanup";

/** How long a dictation that landed stays on the key before it goes back to resting. */
const DONE_DWELL_MS = 1500;

/** Phases that end a dictation, one way or another. */
const TERMINAL_PHASES = ["done", "empty", "error"];

/** Ends that the user has to be told about, because nothing was pasted. */
const FAILED_PHASES = ["empty", "error"];

export type DictateKeySettings = {
	language?: DictationLanguage;
	output?: DictationOutput;
};

export type DictateDependencies = KeyDependencies & {
	/**
	 * Listens to the microphone level while a dictation runs.
	 * @param listener Function called with each level.
	 * @returns A function that stops the listening.
	 */
	onLevel: (listener: (value: number) => void) => () => void;
};

/**
 * Where the label of an output lives in the translation files.
 * @param output What the app does with the dictation.
 * @returns The translation key.
 */
export function outputLabelKey(output: DictationOutput): string {
	return `dictate.${output}.label`;
}

export class DictateKey extends SingletonAction<DictateKeySettings> {
	public override readonly manifestId = DICTATE_UUID;

	readonly #deps: DictateDependencies;
	readonly #painter = new KeyPainter();
	readonly #settings = new Map<string, DictateKeySettings>();

	/** The levels the keys show; every key of the page shows the same ones. */
	readonly #meter = new LevelMeter(() => void this.#drawAll(this.#deps.store.snapshot, null));

	/** Runs while a dictation that landed is still worth showing. */
	#doneDwell: ReturnType<typeof setTimeout> | null = null;

	/** Whether the dictation that landed has had its moment on the key. */
	#doneShown = false;

	/** The phase of the dictation, as of the last frame; `null` when there is none. */
	#phase: string | null = null;

	/**
	 * The key whose press started the dictation in flight, if a key did. A dictation
	 * started from the keyboard belongs to no key, and warns none.
	 */
	#pressedKeyId: string | null = null;

	/**
	 * The keys whose own `down` went out and that have not come up yet. A release only
	 * ends what its own key started: an `up` on its own would stop a dictation somebody
	 * else began, or one that never began at all.
	 */
	readonly #holding = new Set<string>();

	public constructor(deps: DictateDependencies) {
		super();
		this.#deps = deps;
		deps.store.onChange((snapshot) => void this.#changed(snapshot));
		deps.onLevel((value) => this.#heard(value));
	}

	public override async onWillAppear(ev: WillAppearEvent<DictateKeySettings>): Promise<void> {
		this.#settings.set(ev.action.id, ev.payload.settings);
		if (ev.action.isKey()) {
			await this.#draw(ev.action, ev.payload.settings, this.#deps.store.snapshot);
		}
	}

	public override onWillDisappear(ev: WillDisappearEvent<DictateKeySettings>): void {
		this.#settings.delete(ev.action.id);
		this.#painter.forget(ev.action);
		// There is no longer a key to warn, and the identifier could come back as another.
		this.#forgetPress(ev.action.id);
	}

	public override async onDidReceiveSettings(ev: DidReceiveSettingsEvent<DictateKeySettings>): Promise<void> {
		this.#settings.set(ev.action.id, ev.payload.settings);
		if (ev.action.isKey()) {
			await this.#draw(ev.action, ev.payload.settings, this.#deps.store.snapshot);
		}
	}

	public override async onKeyDown(ev: KeyDownEvent<DictateKeySettings>): Promise<void> {
		this.#deps.touch(ev.action.device.id);
		if (!this.#deps.store.snapshot.connected) {
			await ev.action.showAlert();
			this.#forgetPress(ev.action.id);
			await this.#deps.openClaudio();
			return;
		}

		const { language = DEFAULT_LANGUAGE, output = DEFAULT_OUTPUT } = ev.payload.settings;
		// The connection can still go between that check and the write.
		if (!this.#deps.bridge.send({ type: "dictation", event: "down", language, output })) {
			await ev.action.showAlert();
			this.#forgetPress(ev.action.id);
			return;
		}

		this.#holding.add(ev.action.id);
		this.#pressedKeyId = ev.action.id;
	}

	public override async onKeyUp(ev: KeyUpEvent<DictateKeySettings>): Promise<void> {
		if (!this.#holding.delete(ev.action.id)) {
			// This key's press never went out, so there is nothing of its own to end.
			return;
		}

		// Whatever the app is doing by now, the key coming up ends the dictation.
		if (!this.#deps.bridge.send({ type: "dictation", event: "up" })) {
			await ev.action.showAlert();
		}
	}

	/**
	 * Forgets a press of one key: the key is gone, or its press never left the plugin.
	 * Only the key that owns a press may forget it.
	 * @param id Identifier of the key.
	 */
	#forgetPress(id: string): void {
		this.#holding.delete(id);
		if (this.#pressedKeyId === id) {
			this.#pressedKeyId = null;
		}
	}

	/**
	 * Follows the dictation from one frame to the next, then redraws.
	 * @param snapshot What the keys draw from.
	 */
	async #changed(snapshot: StoreSnapshot): Promise<void> {
		const warnFor = this.#follow(snapshot);
		await this.#drawAll(snapshot, warnFor);
	}

	/**
	 * Keeps the timers and the meter in step with the phase the app reports, and names the
	 * key to warn when a dictation ends with nothing to show for it.
	 * @param snapshot What the keys draw from.
	 * @returns The key to warn, or `null`.
	 */
	#follow(snapshot: StoreSnapshot): string | null {
		const phase = dictationPhase(snapshot);
		if (phase === this.#phase) {
			return null;
		}

		this.#phase = phase;
		if (phase !== "listening") {
			this.#meter.forget();
		}

		this.#doneShown = false;
		this.#cancelDwell();
		if (phase === "done") {
			this.#doneDwell = setTimeout(() => this.#doneDwelt(), DONE_DWELL_MS);
		}

		if (phase === null || !TERMINAL_PHASES.includes(phase)) {
			return null;
		}

		// The dictation is over: whatever comes next belongs to another press.
		const pressed = this.#pressedKeyId;
		this.#pressedKeyId = null;

		return FAILED_PHASES.includes(phase) ? pressed : null;
	}

	/** Takes the key back to resting once a dictation that landed has been seen. */
	#doneDwelt(): void {
		this.#doneDwell = null;
		this.#doneShown = true;
		void this.#drawAll(this.#deps.store.snapshot, null);
	}

	/** Forgets a dwell that has not run yet. */
	#cancelDwell(): void {
		if (this.#doneDwell !== null) {
			clearTimeout(this.#doneDwell);
			this.#doneDwell = null;
		}
	}

	/**
	 * Takes in a level from the app, and redraws the meter if it is time to.
	 * @param value The level, between zero and one.
	 */
	#heard(value: number): void {
		if (dictationPhase(this.#deps.store.snapshot) !== "listening") {
			return;
		}

		this.#meter.hear(value);
	}

	/**
	 * The state the keys are following, or `null` when they follow none.
	 * @param snapshot What the keys draw from.
	 * @returns The state to draw, or `null` to rest.
	 */
	#showing(snapshot: StoreSnapshot): BridgeState | null {
		const state = snapshot.state;
		if (state === null || state.activity !== "dictation") {
			return null;
		}

		// The text landed a while ago: the key has said so long enough.
		return state.phase === "done" && this.#doneShown ? null : state;
	}

	/**
	 * Redraws every visible key, and warns the one whose dictation came to nothing.
	 * @param snapshot What the keys draw from.
	 * @param warnFor Key to warn, if any.
	 */
	async #drawAll(snapshot: StoreSnapshot, warnFor: string | null): Promise<void> {
		for (const action of this.actions) {
			if (!action.isKey()) {
				continue;
			}

			await this.#draw(action, this.#settings.get(action.id) ?? {}, snapshot);
			if (action.id === warnFor) {
				await action.showAlert();
			}
		}
	}

	/**
	 * Draws one key.
	 * @param action Key to draw on.
	 * @param settings What that key carries.
	 * @param snapshot What the keys draw from.
	 */
	async #draw(action: PaintableKey, settings: DictateKeySettings, snapshot: StoreSnapshot): Promise<void> {
		const look = dictateLook({
			state: this.#showing(snapshot),
			levels: this.#meter.levels,
			restLabel: this.#deps.translate(outputLabelKey(settings.output ?? DEFAULT_OUTPUT)),
			translate: this.#deps.translate,
		});

		await this.#painter.paint(
			action,
			keySvg({ glyph: look.glyph, label: look.label, state: look.state, dimmed: !snapshot.connected }),
		);
	}
}

/**
 * The phase of the dictation the app is running, if it is running one.
 * @param snapshot What the keys draw from.
 * @returns The phase, or `null`.
 */
function dictationPhase(snapshot: StoreSnapshot): string | null {
	const state = snapshot.state;

	return state !== null && state.activity === "dictation" ? state.phase : null;
}
