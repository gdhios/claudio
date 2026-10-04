/**
 * What a Dictate key shows at a given moment.
 *
 * A pure reading of the app's state: no key, no timer, no Stream Deck. The key itself
 * decides which moment to ask about — a dictation that finished stays on screen for a
 * short while before the key goes back to resting.
 */

import type { BridgeState } from "../bridge/protocol.js";
import { mascot, micGlyph } from "./glyphs.js";

/** The moments a Dictate key can be in, as written into the drawing. */
export type DictateKeyState = "rest" | "listening" | "locked" | "working" | "done";

/** Phases the app reports while it is still turning what was said into text. */
const WORKING_PHASES = ["finishing", "cleaning", "pasting"];

/**
 * What the key says at each moment it is not resting. These are translation keys under
 * `dictate.` — a resting key says the label of its own settings instead.
 */
export const DICTATE_PHRASES = ["listening", "locked", "working", "done"] as const;

export type DictatePhrase = (typeof DICTATE_PHRASES)[number];

export type DictateLookInput = {
	/**
	 * The state the key is following, or `null` when it follows none: nothing was ever
	 * said, the app is busy with something else, or the key has shown a finished
	 * dictation long enough.
	 */
	state: BridgeState | null;

	/** The levels last heard, oldest first. */
	levels: readonly number[];

	/** What the key says when it is resting, from its own settings. */
	restLabel: string;

	/** Looks a label up in the translation files. */
	translate: (key: string) => string;
};

export type DictateLook = {
	/** The moment this drawing stands for. */
	state: DictateKeyState;

	/** The glyph to put on the key. */
	glyph: string;

	/** The label to bake under it. */
	label: string;
};

/**
 * Reads the app's state as a key drawing.
 * @param input The state, what has been heard, and where the words come from.
 * @returns What to draw.
 */
export function dictateLook(input: DictateLookInput): DictateLook {
	const { state, levels, restLabel, translate } = input;
	const rest: DictateLook = { state: "rest", glyph: micGlyph(), label: restLabel };
	const say = (phrase: DictatePhrase): string => translate(`dictate.${phrase}`);

	if (state === null || state.activity !== "dictation" || state.phase === null) {
		return rest;
	}

	if (state.phase === "listening") {
		return state.locked
			? { state: "locked", glyph: micGlyph({ levels, locked: true }), label: say("locked") }
			: { state: "listening", glyph: micGlyph({ levels }), label: say("listening") };
	}

	if (WORKING_PHASES.includes(state.phase)) {
		// The app names the step it is on, in its own language; that beats a guess.
		return { state: "working", glyph: mascot("veille"), label: state.label ?? say("working") };
	}

	if (state.phase === "done") {
		return { state: "done", glyph: mascot("fait"), label: say("done") };
	}

	// `empty`, `error`, and whatever the app learns to say next: the key has nothing to show.
	return rest;
}
