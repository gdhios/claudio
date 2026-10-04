/**
 * Stand-ins shared by more than one suite. Nothing here talks to the network, to Stream
 * Deck or to the filesystem.
 */

import { vi } from "vitest";

import { SVG_DATA_URI_PREFIX } from "../src/render/uri.js";
import type { BridgeFeed } from "../src/state/follow.js";
import { Store } from "../src/state/store.js";

export type FakeBridge = {
	/** What `followBridge` listens to. */
	feed: BridgeFeed;

	/** Plays an event the real client would emit. */
	emit: (event: string, ...args: unknown[]) => void;
};

/**
 * The bridge, as far as the store can tell.
 * @returns The fake and its trigger.
 */
export function fakeBridgeFeed(): FakeBridge {
	const listeners = new Map<string, Set<(...args: never[]) => void>>();

	return {
		feed: {
			on(event: string, listener: (...args: never[]) => void): () => void {
				const set = listeners.get(event) ?? new Set();
				listeners.set(event, set);
				set.add(listener);

				return () => set.delete(listener);
			},
		} as unknown as BridgeFeed,
		emit(event: string, ...args: unknown[]): void {
			for (const listener of [...(listeners.get(event) ?? [])]) {
				(listener as (...a: unknown[]) => void)(...args);
			}
		},
	};
}

/** The deck the fake keys of a suite sit on, unless the suite says otherwise. */
export const DECK = "deck-red";

/**
 * A key on the hardware, as far as an action can tell.
 * @param id Identifier of the key.
 * @param deviceId Deck it sits on.
 * @returns The stand-in.
 */
export function fakeKey(id = "key-1", deviceId = DECK) {
	return {
		id,
		device: { id: deviceId },
		isKey: () => true,
		setImage: vi.fn(async (_image: string) => {}),
		setTitle: vi.fn(async (_title: string) => {}),
		setSettings: vi.fn(async (_settings: object) => {}),
		showAlert: vi.fn(async () => {}),
		showOk: vi.fn(async () => {}),
	};
}

export type FakeKey = ReturnType<typeof fakeKey>;

/**
 * Reads back the SVG a fake key's `setImage` was actually given.
 *
 * Production code wraps every drawing as a data URI before handing it to Stream Deck;
 * a suite asserting on the drawing itself should not have to know that.
 * @param image What `setImage` was called with.
 * @returns The SVG document.
 */
export function decodeImage(image: string): string {
	return image.startsWith(SVG_DATA_URI_PREFIX)
		? Buffer.from(image.slice(SVG_DATA_URI_PREFIX.length), "base64").toString("utf8")
		: image;
}

/**
 * The collaborators every key is built with.
 * @returns The stand-ins.
 */
export function fakeKeyDeps() {
	return {
		bridge: { send: vi.fn(() => true) },
		store: new Store(),
		openClaudio: vi.fn(async () => {}),
		translate: (key: string): string => `[${key}]`,
		touch: vi.fn(),
		// The blink is timed, so a suite that waits knows exactly when the eyes close.
		random: () => 0,
	};
}

/**
 * Plays Stream Deck showing a key.
 * @param action Action under test.
 * @param key The key.
 * @param settings Settings the key carries.
 * @param coordinates Where it sits, for the actions that care.
 */
export async function appear(
	action: { onWillAppear?: (ev: never) => Promise<void> | void },
	key: FakeKey,
	settings: object = {},
	coordinates?: { column: number; row: number },
): Promise<void> {
	await action.onWillAppear?.({ action: key, payload: { settings, coordinates } } as never);
}

/**
 * Plays Stream Deck taking a key off the screen.
 * @param action Action under test.
 * @param key The key.
 * @param settings Settings the key carries.
 */
export async function disappear(
	action: { onWillDisappear?: (ev: never) => Promise<void> | void },
	key: FakeKey,
	settings: object = {},
): Promise<void> {
	await action.onWillDisappear?.({ action: key, payload: { settings } } as never);
}

/**
 * Plays a press.
 * @param action Action under test.
 * @param key The key.
 * @param settings Settings the key carries.
 */
export async function press(
	action: { onKeyDown?: (ev: never) => Promise<void> | void },
	key: FakeKey,
	settings: object = {},
): Promise<void> {
	await action.onKeyDown?.({ action: key, payload: { settings } } as never);
}
