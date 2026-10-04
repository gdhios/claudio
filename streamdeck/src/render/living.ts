/**
 * The key Claudio himself sits on.
 *
 * Two keys draw it: the standalone Claudio key, and the navigation key that takes a deck
 * back to the face. They are the same key to the user — the mascot, under his name — so
 * they are the same drawing here.
 */

import type { Gaze } from "../bridge/protocol.js";
import { mascot } from "./glyphs.js";
import { keySvg } from "./key.js";
import { theme } from "./theme.js";

export type LivingKeyOptions = {
	/** The look he is wearing. */
	gaze: Gaze;

	/** What is written under him. */
	label: string;

	/** Draws the key faded, for when nobody answers. */
	dimmed?: boolean;
};

/**
 * Draws the mascot on a key.
 * @param options What to draw.
 * @returns The SVG document.
 */
export function livingKeySvg(options: LivingKeyOptions): string {
	const { gaze, label, dimmed = false } = options;

	return keySvg({ glyph: mascot(gaze), label, labelColor: theme.accent, dimmed, state: gaze });
}
