/**
 * The Window key: sends the frontmost window somewhere.
 *
 * It belongs to the darker family — this is a different tool from the text actions, and
 * the drawing says so before the label would. There is no label: the glyph is the label.
 */

import {
	type DidReceiveSettingsEvent,
	type KeyDownEvent,
	SingletonAction,
	type WillAppearEvent,
	type WillDisappearEvent,
} from "@elgato/streamdeck";

import type { WindowLayout } from "../bridge/protocol.js";
import { windowLayout } from "../render/glyphs.js";
import { keySvg } from "../render/key.js";
import type { StoreSnapshot } from "../state/store.js";
import { type KeyDependencies, KeyPainter, type PaintableKey } from "./keys.js";

/** Identifier of this action in the manifest. */
export const WINDOW_UUID = "com.okonoma.claudio.window";

/** What a fresh key does. */
export const DEFAULT_WINDOW_LAYOUT: WindowLayout = "leftHalf";

export type WindowKeySettings = {
	layout?: WindowLayout;
};

export class WindowKey extends SingletonAction<WindowKeySettings> {
	public override readonly manifestId = WINDOW_UUID;

	readonly #deps: KeyDependencies;
	readonly #painter = new KeyPainter();
	readonly #settings = new Map<string, WindowKeySettings>();

	public constructor(deps: KeyDependencies) {
		super();
		this.#deps = deps;
		deps.store.onChange((snapshot) => void this.#redrawAll(snapshot));
	}

	public override async onWillAppear(ev: WillAppearEvent<WindowKeySettings>): Promise<void> {
		this.#settings.set(ev.action.id, ev.payload.settings);
		if (ev.action.isKey()) {
			await this.#draw(ev.action, ev.payload.settings, this.#deps.store.snapshot);
		}
	}

	public override onWillDisappear(ev: WillDisappearEvent<WindowKeySettings>): void {
		this.#settings.delete(ev.action.id);
		this.#painter.forget(ev.action);
	}

	public override async onDidReceiveSettings(ev: DidReceiveSettingsEvent<WindowKeySettings>): Promise<void> {
		this.#settings.set(ev.action.id, ev.payload.settings);
		if (ev.action.isKey()) {
			await this.#draw(ev.action, ev.payload.settings, this.#deps.store.snapshot);
		}
	}

	public override async onKeyDown(ev: KeyDownEvent<WindowKeySettings>): Promise<void> {
		this.#deps.touch(ev.action.device.id);
		if (!this.#deps.store.snapshot.connected) {
			await ev.action.showAlert();
			await this.#deps.openClaudio();
			return;
		}

		// The connection can still go between that check and the write.
		if (!this.#deps.bridge.send({ type: "window", layout: ev.payload.settings.layout ?? DEFAULT_WINDOW_LAYOUT })) {
			await ev.action.showAlert();
		}
	}

	/**
	 * Redraws every visible key.
	 * @param snapshot What the keys draw from.
	 */
	async #redrawAll(snapshot: StoreSnapshot): Promise<void> {
		for (const action of this.actions) {
			if (action.isKey()) {
				await this.#draw(action, this.#settings.get(action.id) ?? {}, snapshot);
			}
		}
	}

	/**
	 * Draws one key.
	 * @param action Key to draw on.
	 * @param settings What that key carries.
	 * @param snapshot What the keys draw from.
	 */
	async #draw(
		action: PaintableKey,
		settings: WindowKeySettings,
		snapshot: StoreSnapshot,
	): Promise<void> {
		await this.#painter.paint(
			action,
			keySvg({
				glyph: windowLayout(settings.layout ?? DEFAULT_WINDOW_LAYOUT),
				background: "dark",
				dimmed: !snapshot.connected,
			}),
		);
	}
}
