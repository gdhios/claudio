import { describe, expect, it, vi } from "vitest";

import type { BridgeState } from "../src/bridge/protocol.js";
import { Store } from "../src/state/store.js";

const idle: BridgeState = { gaze: "repos", activity: "idle", phase: null, label: null, locked: false };
const streaming: BridgeState = {
	gaze: "veille",
	activity: "correction",
	phase: "streaming",
	label: "Correction…",
	locked: false,
};

describe("Store", () => {
	it("starts disconnected, with no state, and assumes the app is running", () => {
		// Stream Deck only reports the app on launch and on quit, never at startup, so the
		// store begins where the bridge does: running until told otherwise.
		expect(new Store().snapshot).toEqual({ state: null, connected: false, claudioRunning: true });
	});

	it("tells its listeners what changed", () => {
		const store = new Store();
		const listener = vi.fn();
		store.onChange(listener);

		store.setConnected(true);
		store.setState(streaming);

		expect(listener).toHaveBeenCalledTimes(2);
		expect(listener).toHaveBeenLastCalledWith({ state: streaming, connected: true, claudioRunning: true });
	});

	it("stays quiet when nothing actually changed", () => {
		const store = new Store();
		store.setState(idle);
		const listener = vi.fn();
		store.onChange(listener);

		store.setState({ ...idle });
		store.setConnected(false);

		expect(listener).not.toHaveBeenCalled();
	});

	it("notices a state that differs by a single field", () => {
		const store = new Store();
		store.setState(idle);
		const listener = vi.fn();
		store.onChange(listener);

		store.setState({ ...idle, locked: true });

		expect(listener).toHaveBeenCalledOnce();
	});

	it("tells its listeners once about fields that change together", () => {
		const store = new Store();
		store.update({ connected: true, state: streaming });
		const listener = vi.fn();
		store.onChange(listener);

		store.update({ connected: false, state: null });

		expect(listener).toHaveBeenCalledOnce();
		expect(listener).toHaveBeenCalledWith({ state: null, connected: false, claudioRunning: true });
	});

	it("stops telling a listener that unsubscribed", () => {
		const store = new Store();
		const listener = vi.fn();
		const unsubscribe = store.onChange(listener);

		unsubscribe();
		store.setClaudioRunning(false);

		expect(listener).not.toHaveBeenCalled();
	});
});
