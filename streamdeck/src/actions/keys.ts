/**
 * What both key types share: who they talk to, and how a drawing reaches the hardware.
 */

import type { ImageOptions, TitleOptions } from "@elgato/streamdeck";

import type { BridgeClient } from "../bridge/client.js";
import { svgDataUri } from "../render/uri.js";
import type { Store } from "../state/store.js";

export type KeyDependencies = {
	/** Where a press goes. */
	bridge: Pick<BridgeClient, "send">;

	/** What the key draws from. */
	store: Store;

	/** Called when a press lands with nobody at the other end. */
	openClaudio: () => Promise<void>;

	/** Looks a label up in the translation files. */
	translate: (key: string) => string;

	/**
	 * Called on every press, with the deck the key sits on: a deck being played is not a
	 * deck left alone, and must not be taken back to the face under the user's finger.
	 */
	touch: (deviceId: string) => void;

	/** Where the blink's pace comes from; injected so a test can pin it down. */
	random?: () => number;
};

/** The little of a key the painter needs. */
export type PaintableKey = {
	readonly id: string;
	setTitle(title?: string, options?: TitleOptions): Promise<void>;
	setImage(image?: string, options?: ImageOptions): Promise<void>;
};

/**
 * How long a key is left alone after a drawing goes out.
 *
 * Stream Deck accepts ten images a second on one key. A tenth of a second exactly would
 * still allow eleven of them inside one rolling second, so the floor is a little higher.
 */
export const PAINT_FLOOR_MS = 110;

/** What the painter remembers about one key. */
type KeyPaint = {
	/** The last drawing the key confirmed taking. */
	drawn: string | null;

	/** The last drawing handed to the key, landed or still on its way. */
	target: string | null;

	/** A drawing asked for that the floor is holding back. */
	held: string | null;

	/** Runs while the floor holds; `null` when a drawing may go out. */
	timer: ReturnType<typeof setTimeout> | null;

	/** When the last drawing went out. */
	at: number;

	/** The writes of this key, one after another. */
	chain: Promise<void>;
};

/**
 * Sends drawings to keys, no faster than the hardware takes them.
 *
 * Three things at once, all of them per key. A drawing that says what the key already
 * carries is not sent. Drawings that come faster than the floor are dropped, except the
 * last one, which goes out when the floor passes — so the key always ends up showing the
 * newest thing asked of it. And the writes of one key are chained, so two redraws
 * crossing each other cannot leave the older one on top.
 */
export class KeyPainter {
	readonly #keys = new Map<string, KeyPaint>();

	/**
	 * Draws a key, when the key can take it.
	 * @param key Key to draw on.
	 * @param image The drawing.
	 * @returns A promise that settles once the writes already under way have.
	 */
	public async paint(key: PaintableKey, image: string): Promise<void> {
		const paint = this.#paintOf(key.id);
		paint.held = image;
		this.#schedule(key, paint);

		return paint.chain;
	}

	/**
	 * Forgets a key that is no longer on screen: it comes back as a blank key, and
	 * whatever was being held for it is not worth drawing any more.
	 * @param key The key.
	 */
	public forget(key: { readonly id: string }): void {
		const paint = this.#keys.get(key.id);
		if (paint?.timer != null) {
			clearTimeout(paint.timer);
		}

		this.#keys.delete(key.id);
	}

	/**
	 * What the painter remembers about a key, from the first time it draws it.
	 * @param id Identifier of the key.
	 * @returns Its state.
	 */
	#paintOf(id: string): KeyPaint {
		const known = this.#keys.get(id);
		if (known !== undefined) {
			return known;
		}

		const fresh: KeyPaint = { drawn: null, target: null, held: null, timer: null, at: 0, chain: Promise.resolve() };
		this.#keys.set(id, fresh);

		return fresh;
	}

	/**
	 * Draws what is held now, or waits for the floor to pass.
	 * @param key Key to draw on.
	 * @param paint What the painter remembers about it.
	 */
	#schedule(key: PaintableKey, paint: KeyPaint): void {
		if (paint.timer !== null) {
			// A drawing is already due; it will pick up whatever is held by then.
			return;
		}

		const wait = PAINT_FLOOR_MS - (Date.now() - paint.at);
		if (wait <= 0) {
			this.#write(key, paint);
			return;
		}

		paint.timer = setTimeout(() => {
			paint.timer = null;
			this.#write(key, paint);
		}, wait);
	}

	/**
	 * Hands the drawing being held to the key.
	 * @param key Key to draw on.
	 * @param paint What the painter remembers about it.
	 */
	#write(key: PaintableKey, paint: KeyPaint): void {
		const image = paint.held;
		paint.held = null;
		if (image === null || image === paint.target) {
			return;
		}

		paint.target = image;
		paint.at = Date.now();
		paint.chain = paint.chain
			.then(async () => {
				// Stream Deck's own title would sit on top of the drawing; the label is baked in.
				await key.setTitle("");
				// The app only takes an image as a data URI; a bare SVG string is ignored.
				await key.setImage(svgDataUri(image));
				paint.drawn = image;
			})
			.catch(() => {
				// The key never took it, so it must not be remembered as the one it carries:
				// nothing else would ever send it again.
				if (paint.target === image) {
					paint.target = paint.drawn;
				}
			});
	}
}
