/**
 * What the bridge tells the store.
 *
 * A connection that drops takes the state with it. The app is no longer there to say
 * when the dictation it was running ends, so its last word — listening, streaming — is
 * not news any more; left in the store it would freeze every key on a moment that is
 * over, for as long as the plugin runs.
 */

import type { BridgeClient } from "../bridge/client.js";
import type { Store } from "./store.js";

/** The little of the bridge the store needs. */
export type BridgeFeed = Pick<BridgeClient, "on">;

/**
 * Keeps the store in step with the bridge.
 * @param bridge The connection to the app.
 * @param store What the keys draw from.
 */
export function followBridge(bridge: BridgeFeed, store: Store): void {
	bridge.on("connected", () => {
		// A connection is proof the app is running, which Stream Deck only reports on launch.
		store.update({ claudioRunning: true, connected: true });
	});

	bridge.on("disconnected", () => {
		// One change, not two: a key told only that the connection went would redraw the
		// dictation it still reads in the store, dimmed, before the state drops.
		store.update({ connected: false, state: null });
	});

	bridge.on("state", (state) => store.setState(state));
}
