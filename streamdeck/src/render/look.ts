/**
 * What the mascot shows at a given moment, whether he is on one key or on fifteen.
 *
 * A pure reading of the app's state: no key, no timer, no Stream Deck. The rules are the
 * same for the Claudio key and for the face, which is why they live here rather than in
 * either of them.
 */

import type { BridgeState, Gaze } from "../bridge/protocol.js";
import type { FaceParams } from "./face.js";

export type LookInput = {
	/** The last state the app sent, or `null` when it never sent one. */
	state: BridgeState | null;

	/** Whether anybody is at the other end. */
	connected: boolean;

	/** Whether the blink has his eyes shut at this instant. */
	eyesClosed: boolean;
};

export type FaceLookInput = LookInput & {
	/** How loud the voice is, between zero and one. */
	level: number;

	/** What to write across the middle key while nobody answers. */
	message: string;
};

/**
 * The look the mascot wears.
 *
 * A connection that is gone empties his eyes — there is nothing behind them to report.
 * A blink only ever touches the resting look: the three others are what the app is
 * saying, and a blink must not talk over it.
 * @param input What the app is doing, and what the blink is up to.
 * @returns The look.
 */
export function livingGaze(input: LookInput): Gaze {
	const { state, connected, eyesClosed } = input;
	if (!connected) {
		return "vide";
	}

	const gaze = state?.gaze ?? "repos";

	return eyesClosed && gaze === "repos" ? "veille" : gaze;
}

/**
 * Whether the mascot has nothing better to do with his eyes than blink.
 * @param input What the app is doing.
 * @returns `true` when he may blink.
 */
export function mayBlink(input: Pick<LookInput, "state" | "connected">): boolean {
	return input.connected && (input.state?.gaze ?? "repos") === "repos";
}

/**
 * The whole face, as the deck should draw it.
 * @param input What the app is doing, what it sounds like, and what to say if it is gone.
 * @returns The face to draw.
 */
export function faceLook(input: FaceLookInput): FaceParams {
	const { state, connected, level, message } = input;

	return {
		gaze: livingGaze(input),
		// A voice that stopped reaching us leaves the moustache where it was; flatten it.
		level: connected ? level : 0,
		// The antenna is lit while Claudio has something on his hands.
		glow: connected && state !== null && state.activity !== "idle",
		disconnected: !connected,
		message,
	};
}
