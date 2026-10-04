import { beforeEach, describe, expect, it, vi } from "vitest";

import type { BridgeState } from "../src/bridge/protocol.js";
import { followBridge } from "../src/state/follow.js";
import { Store } from "../src/state/store.js";
import { fakeBridgeFeed } from "./fakes.js";

/** A dictation in full flight. */
const LISTENING: BridgeState = {
	gaze: "repos",
	activity: "dictation",
	phase: "listening",
	label: null,
	locked: false,
};

describe("followBridge", () => {
	let bridge: ReturnType<typeof fakeBridgeFeed>;
	let store: Store;

	beforeEach(() => {
		bridge = fakeBridgeFeed();
		store = new Store();
		followBridge(bridge.feed, store);
	});

	it("takes a connection as proof the app is running", () => {
		store.setClaudioRunning(false);

		bridge.emit("connected", LISTENING);

		expect(store.snapshot.connected).toBe(true);
		expect(store.snapshot.claudioRunning).toBe(true);
	});

	it("records every state the app sends", () => {
		bridge.emit("state", LISTENING);

		expect(store.snapshot.state).toEqual(LISTENING);
	});

	it("drops the state along with the connection", () => {
		bridge.emit("connected", LISTENING);
		bridge.emit("state", LISTENING);

		bridge.emit("disconnected");

		// Nobody is left to say when that dictation ends, so it cannot stay on the keys.
		expect(store.snapshot.connected).toBe(false);
		expect(store.snapshot.state).toBeNull();
	});

	it("drops both in one breath, so no key draws the moment in between", () => {
		bridge.emit("connected", LISTENING);
		bridge.emit("state", LISTENING);
		const listener = vi.fn();
		store.onChange(listener);

		bridge.emit("disconnected");

		// Two changes would have every key draw the dictation dimmed before it drops it.
		expect(listener).toHaveBeenCalledTimes(1);
		expect(listener).toHaveBeenCalledWith({ state: null, connected: false, claudioRunning: true });
	});
});
