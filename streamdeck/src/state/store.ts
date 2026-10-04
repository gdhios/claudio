/**
 * What the keys draw from: the last state the app sent, and whether there is anybody to
 * send to. Nothing here talks to Stream Deck or to the bridge; both push into it.
 */

import type { BridgeState } from "../bridge/protocol.js";

export type StoreSnapshot = {
	/** The last state the app sent, or `null` when it never has. */
	state: BridgeState | null;

	/** Whether the bridge has completed its handshake. */
	connected: boolean;

	/**
	 * Whether Claudio is running at all, as Stream Deck reports it.
	 *
	 * Stream Deck only says so when the app launches or quits, never at startup, so this
	 * begins as `true` — running until told otherwise, the same assumption the bridge
	 * makes. Starting from `false` would have the plugin claim the app is absent for as
	 * long as it happened to already be running.
	 */
	claudioRunning: boolean;
};

export type StoreListener = (snapshot: StoreSnapshot) => void;

export class Store {
	#snapshot: StoreSnapshot = { state: null, connected: false, claudioRunning: true };
	readonly #listeners = new Set<StoreListener>();

	/**
	 * The current snapshot.
	 * @returns The snapshot.
	 */
	public get snapshot(): StoreSnapshot {
		return this.#snapshot;
	}

	/**
	 * Records the state the app sent.
	 * @param state The state.
	 */
	public setState(state: BridgeState | null): void {
		this.#update({ state });
	}

	/**
	 * Records whether the bridge is connected.
	 * @param connected Whether it is.
	 */
	public setConnected(connected: boolean): void {
		this.#update({ connected });
	}

	/**
	 * Records whether Claudio is running.
	 * @param claudioRunning Whether it is.
	 */
	public setClaudioRunning(claudioRunning: boolean): void {
		this.#update({ claudioRunning });
	}

	/**
	 * Records several fields at once, as one change.
	 *
	 * Two facts that become true together must reach the keys together: setting them one
	 * after the other draws the moment in between, which never existed.
	 * @param change Fields to change.
	 */
	public update(change: Partial<StoreSnapshot>): void {
		this.#update(change);
	}

	/**
	 * Listens for changes.
	 * @param listener Function called with the new snapshot.
	 * @returns A function that stops the listening.
	 */
	public onChange(listener: StoreListener): () => void {
		this.#listeners.add(listener);

		return () => this.#listeners.delete(listener);
	}

	/**
	 * Applies a change and tells the listeners, unless nothing moved.
	 * @param change Fields to change.
	 */
	#update(change: Partial<StoreSnapshot>): void {
		const next = { ...this.#snapshot, ...change };
		if (isSame(next, this.#snapshot)) {
			return;
		}

		this.#snapshot = next;
		for (const listener of [...this.#listeners]) {
			listener(next);
		}
	}
}

/**
 * Compares two snapshots field by field.
 * @param a One snapshot.
 * @param b The other.
 * @returns `true` when they say the same thing.
 */
function isSame(a: StoreSnapshot, b: StoreSnapshot): boolean {
	return a.connected === b.connected && a.claudioRunning === b.claudioRunning && isSameState(a.state, b.state);
}

/**
 * Compares two states field by field.
 * @param a One state.
 * @param b The other.
 * @returns `true` when they say the same thing.
 */
function isSameState(a: BridgeState | null, b: BridgeState | null): boolean {
	if (a === null || b === null) {
		return a === b;
	}

	return (
		a.gaze === b.gaze &&
		a.activity === b.activity &&
		a.phase === b.phase &&
		a.label === b.label &&
		a.locked === b.locked
	);
}
