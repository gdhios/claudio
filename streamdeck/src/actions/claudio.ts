/**
 * The Claudio key: the mascot himself, and the door to everything he can do.
 *
 * He wears whatever the app is doing, and blinks while it does nothing. Pressing him
 * opens Claudio's palette, where the actions that did not earn a key of their own live.
 */

import {
	type KeyDownEvent,
	SingletonAction,
	type WillAppearEvent,
	type WillDisappearEvent,
} from "@elgato/streamdeck";

import { livingKeySvg } from "../render/living.js";
import { livingGaze, mayBlink } from "../render/look.js";
import type { StoreSnapshot } from "../state/store.js";
import { Blink } from "./blink.js";
import { type KeyDependencies, KeyPainter, type PaintableKey } from "./keys.js";

/** Identifier of this action in the manifest. */
export const CLAUDIO_UUID = "com.okonoma.claudio.claudio";

/** Where his own name lives in the translation files. */
export const CLAUDIO_LABEL_KEY = "claudio.label";

/** What the property inspector's button sends. */
export const INSTALL_PROFILE_EVENT = "installProfile";

/** A message from the property inspector, as the base class types it. */
type InspectorMessage = Parameters<NonNullable<SingletonAction["onSendToPlugin"]>>[0];

export type ClaudioDependencies = KeyDependencies & {
	/**
	 * Takes a deck to the Claudio profile's face page — installing the profile first when
	 * the deck does not have it yet. Only the plugin can install its own profile, so the
	 * key's inspector carries the button that asks for it.
	 */
	installProfile: (deviceId: string) => Promise<void>;
};

export class ClaudioKey extends SingletonAction {
	public override readonly manifestId = CLAUDIO_UUID;

	readonly #deps: ClaudioDependencies;
	readonly #painter = new KeyPainter();
	readonly #blink: Blink;

	public constructor(deps: ClaudioDependencies) {
		super();
		this.#deps = deps;
		this.#blink = new Blink(() => void this.#drawAll(deps.store.snapshot), deps.random);
		deps.store.onChange((snapshot) => void this.#changed(snapshot));
	}

	public override async onWillAppear(ev: WillAppearEvent): Promise<void> {
		const snapshot = this.#deps.store.snapshot;
		this.#blink.follow(mayBlink(snapshot));
		if (ev.action.isKey()) {
			await this.#draw(ev.action, snapshot);
		}
	}

	public override onWillDisappear(ev: WillDisappearEvent): void {
		this.#painter.forget(ev.action);
	}

	public override async onSendToPlugin(ev: InspectorMessage): Promise<void> {
		const payload = ev.payload;
		if (typeof payload === "object" && payload !== null && !Array.isArray(payload) && payload.event === INSTALL_PROFILE_EVENT) {
			await this.#deps.installProfile(ev.action.device.id);
		}
	}

	public override async onKeyDown(ev: KeyDownEvent): Promise<void> {
		this.#deps.touch(ev.action.device.id);
		if (!this.#deps.store.snapshot.connected) {
			await ev.action.showAlert();
			await this.#deps.openClaudio();

			return;
		}

		// The connection can still go between that check and the write.
		if (!this.#deps.bridge.send({ type: "action", id: "palette" })) {
			await ev.action.showAlert();
		}
	}

	/** Stops the blinking, for when the plugin is done with this action. */
	public stop(): void {
		this.#blink.stop();
	}

	/**
	 * Follows the app, and redraws.
	 * @param snapshot What the keys draw from.
	 */
	async #changed(snapshot: StoreSnapshot): Promise<void> {
		this.#blink.follow(mayBlink(snapshot));
		await this.#drawAll(snapshot);
	}

	/**
	 * Redraws every visible key.
	 * @param snapshot What the keys draw from.
	 */
	async #drawAll(snapshot: StoreSnapshot): Promise<void> {
		for (const action of this.actions) {
			if (action.isKey()) {
				await this.#draw(action, snapshot);
			}
		}
	}

	/**
	 * Draws one key.
	 * @param action Key to draw on.
	 * @param snapshot What the keys draw from.
	 */
	async #draw(action: PaintableKey, snapshot: StoreSnapshot): Promise<void> {
		await this.#painter.paint(
			action,
			livingKeySvg({
				gaze: livingGaze({ ...snapshot, eyesClosed: this.#blink.closed }),
				label: this.#deps.translate(CLAUDIO_LABEL_KEY),
				dimmed: !snapshot.connected,
			}),
		);
	}
}
