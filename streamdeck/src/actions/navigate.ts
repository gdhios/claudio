/**
 * The Navigate key: a door between the profile's three pages, or out of it.
 *
 * It never touches the bridge — it works whether or not Claudio is there to answer — and
 * it draws whichever of four faces its settings ask for, one of which is the mascot
 * himself, alive the same way his own key is.
 */

import {
	type DidReceiveSettingsEvent,
	type KeyDownEvent,
	SingletonAction,
	type WillAppearEvent,
	type WillDisappearEvent,
} from "@elgato/streamdeck";

import type { PageName } from "../idle.js";
import { back, windowsPage } from "../render/glyphs.js";
import { keySvg } from "../render/key.js";
import { livingKeySvg } from "../render/living.js";
import { livingGaze } from "../render/look.js";
import type { Store, StoreSnapshot } from "../state/store.js";
import { CLAUDIO_LABEL_KEY } from "./claudio.js";
import { KeyPainter, type PaintableKey } from "./keys.js";

/** Identifier of this action in the manifest. */
export const NAVIGATE_UUID = "com.okonoma.claudio.navigate";

export type NavigateTarget = "face" | "actions" | "windows" | "leave";

/** Where a key with no settings of its own goes. */
export const DEFAULT_NAVIGATE_TARGET: NavigateTarget = "actions";

export type NavigateKeySettings = {
	target?: NavigateTarget;
};

export type NavigateDependencies = {
	/** What the "face" target draws from. */
	store: Store;

	/** Looks a label up in the translation files. */
	translate: (key: string) => string;

	/** Called on every press, so the deck's own return to the face is put off. */
	touch: (deviceId: string) => void;

	/** Takes a deck to one of the profile's pages, and arms its way back to the face. */
	show: (deviceId: string, page: PageName) => Promise<void>;

	/** Gives a deck back to whatever profile it was showing before. */
	leave: (deviceId: string) => Promise<void>;
};

/**
 * Where a target's label lives in the translation files.
 * @param target The target.
 * @returns The translation key.
 */
function labelKey(target: NavigateTarget): string {
	return target === "face" ? CLAUDIO_LABEL_KEY : `navigate.${target}.label`;
}

export class NavigateKey extends SingletonAction<NavigateKeySettings> {
	public override readonly manifestId = NAVIGATE_UUID;

	readonly #deps: NavigateDependencies;
	readonly #painter = new KeyPainter();
	readonly #settings = new Map<string, NavigateKeySettings>();

	public constructor(deps: NavigateDependencies) {
		super();
		this.#deps = deps;
		deps.store.onChange((snapshot) => void this.#redrawFaces(snapshot));
	}

	public override async onWillAppear(ev: WillAppearEvent<NavigateKeySettings>): Promise<void> {
		this.#settings.set(ev.action.id, ev.payload.settings);
		if (ev.action.isKey()) {
			await this.#draw(ev.action, ev.payload.settings);
		}
	}

	public override onWillDisappear(ev: WillDisappearEvent<NavigateKeySettings>): void {
		this.#settings.delete(ev.action.id);
		this.#painter.forget(ev.action);
	}

	public override async onDidReceiveSettings(ev: DidReceiveSettingsEvent<NavigateKeySettings>): Promise<void> {
		this.#settings.set(ev.action.id, ev.payload.settings);
		if (ev.action.isKey()) {
			await this.#draw(ev.action, ev.payload.settings);
		}
	}

	public override async onKeyDown(ev: KeyDownEvent<NavigateKeySettings>): Promise<void> {
		const deviceId = ev.action.device.id;
		this.#deps.touch(deviceId);
		const target = ev.payload.settings.target ?? DEFAULT_NAVIGATE_TARGET;
		if (target === "leave") {
			await this.#deps.leave(deviceId);

			return;
		}

		await this.#deps.show(deviceId, target);
	}

	/**
	 * Redraws every tile that leads home, since it is the only one that follows the app.
	 * @param snapshot What the "face" target draws from.
	 */
	async #redrawFaces(snapshot: StoreSnapshot): Promise<void> {
		for (const action of this.actions) {
			if (!action.isKey()) {
				continue;
			}

			const settings = this.#settings.get(action.id) ?? {};
			if ((settings.target ?? DEFAULT_NAVIGATE_TARGET) === "face") {
				await this.#painter.paint(action, this.#svg("face", snapshot));
			}
		}
	}

	/**
	 * Draws one key.
	 * @param action Key to draw on.
	 * @param settings What that key carries.
	 */
	async #draw(action: PaintableKey, settings: NavigateKeySettings): Promise<void> {
		const target = settings.target ?? DEFAULT_NAVIGATE_TARGET;
		await this.#painter.paint(action, this.#svg(target, this.#deps.store.snapshot));
	}

	/**
	 * The drawing for one target.
	 * @param target Where the key leads.
	 * @param snapshot What the "face" target draws from.
	 * @returns The SVG document.
	 */
	#svg(target: NavigateTarget, snapshot: StoreSnapshot): string {
		if (target === "face") {
			return livingKeySvg({
				gaze: livingGaze({ state: snapshot.state, connected: snapshot.connected, eyesClosed: false }),
				label: this.#deps.translate(labelKey(target)),
				dimmed: !snapshot.connected,
			});
		}

		const glyph = target === "windows" ? windowsPage() : back();

		return keySvg({ glyph, label: this.#deps.translate(labelKey(target)) });
	}
}
