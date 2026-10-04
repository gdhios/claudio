/**
 * Draws a key as an SVG document.
 *
 * The label is baked into the image rather than left to Stream Deck's own title, which
 * would overlay the drawing; the actions set an empty title for the same reason.
 */

import { escapeAttribute, escapeText } from "./escape.js";
import { KEY_SIZE, theme } from "./theme.js";

/** The two families of key background. */
export type KeyBackground = "violet" | "dark";

export type KeyOptions = {
	/** SVG fragment centred on the glyph centre. */
	glyph: string;

	/** Text baked under the glyph; omitted when the glyph says it all. */
	label?: string;

	/** Draws the key faded, for when nobody can press it. */
	dimmed?: boolean;

	/** Colour of the baked label; white, as the glyphs are, unless it is given. */
	labelColor?: string;

	/** Which family the key belongs to; the violet one by default. */
	background?: KeyBackground;

	/**
	 * What the key is showing, written into the drawing as `data-state`. Nothing reads it
	 * on the hardware; it is how a test names the moment a drawing stands for.
	 */
	state?: string;
};

/** A label, broken into the lines and the size it is drawn at. */
export type BakedLabel = {
	lines: string[];
	fontSize: number;
};

/**
 * Breaks a label into at most two lines and picks the largest size that fits.
 *
 * One line, whole, whenever it fits at the largest size — a key that reads "Ton pro" on
 * one line says it better than one that reads "Ton" above "pro". Two balanced lines are
 * the next choice, because two lines at full size beat one line shrunk to nothing; only
 * then does the size come down.
 * @param label Label to bake.
 * @returns The lines and their font size.
 */
export function bakeLabel(label: string): BakedLabel {
	const { maxFontSize, minFontSize, maxWidth } = theme.label;
	const words = label.trim().split(/\s+/).filter(Boolean);
	const whole = words.join(" ");

	if (words.length === 0 || widthOf(whole, maxFontSize) <= maxWidth) {
		return { lines: words.length === 0 ? [] : [whole], fontSize: maxFontSize };
	}

	const lines = words.length > 1 ? balance(words) : [whole];

	let fontSize = maxFontSize;
	while (fontSize > minFontSize && lines.some((line) => widthOf(line, fontSize) > maxWidth)) {
		fontSize -= 1;
	}

	return { lines, fontSize };
}

/**
 * Draws a key.
 * @param options What to draw.
 * @returns The SVG document.
 */
export function keySvg(options: KeyOptions): string {
	const { glyph, label, dimmed = false, background = "violet", labelColor = theme.ink, state } = options;
	const opacity = dimmed ? ` opacity="${theme.dimmedOpacity}"` : "";
	const named = state === undefined ? "" : ` data-state="${escapeAttribute(state)}"`;

	return [
		`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${KEY_SIZE} ${KEY_SIZE}" width="${KEY_SIZE}" height="${KEY_SIZE}">`,
		background === "violet" ? gradientDefinition() : "",
		`<g${named}${opacity}>`,
		backgroundRect(background),
		glyph,
		label === undefined ? "" : labelText(label, labelColor),
		`</g>`,
		`</svg>`,
	].join("");
}

/**
 * The violet the Claudio keys are cut from.
 * @returns The gradient definition.
 */
function gradientDefinition(): string {
	return [
		`<defs><linearGradient id="claudio-key" x1="0" y1="0" x2="0" y2="1">`,
		`<stop offset="0" stop-color="${theme.gradient.top}"/>`,
		`<stop offset="1" stop-color="${theme.gradient.bottom}"/>`,
		`</linearGradient></defs>`,
	].join("");
}

/**
 * The rounded square the whole key sits on.
 * @param background Which family the key belongs to.
 * @returns The rectangle.
 */
function backgroundRect(background: KeyBackground): string {
	const fill = background === "violet" ? "url(#claudio-key)" : theme.dark.background;

	return `<rect x="0" y="0" width="${KEY_SIZE}" height="${KEY_SIZE}" rx="${theme.radius}" fill="${fill}"/>`;
}

/**
 * The baked label, under the glyph.
 * @param label Label to draw.
 * @param color Colour to draw it in.
 * @returns The text elements, or nothing when the label is blank.
 */
function labelText(label: string, color: string): string {
	const { lines, fontSize } = bakeLabel(label);
	if (lines.length === 0) {
		return "";
	}

	const baselines =
		lines.length === 1
			? [theme.label.singleLineBaseline]
			: [theme.label.firstLineBaseline, theme.label.secondLineBaseline];

	return lines
		.map(
			(line, index) =>
				`<text x="36" y="${baselines[index]}" text-anchor="middle" font-family="${theme.fontFamily}" font-size="${fontSize}" font-weight="700" fill="${color}">${escapeText(line)}</text>`,
		)
		.join("");
}

/**
 * Splits words into the two lines whose longest line is shortest.
 * @param words Words of the label.
 * @returns The two lines.
 */
function balance(words: string[]): string[] {
	let best: string[] = [];
	let bestWidth = Number.POSITIVE_INFINITY;

	for (let breakAt = 1; breakAt < words.length; breakAt++) {
		const lines = [words.slice(0, breakAt).join(" "), words.slice(breakAt).join(" ")];
		const longest = Math.max(...lines.map((line) => line.length));
		if (longest < bestWidth) {
			best = lines;
			bestWidth = longest;
		}
	}

	return best;
}

/**
 * Approximates how wide a line is drawn.
 * @param line Line of text.
 * @param fontSize Size it is drawn at.
 * @returns The width, in user units.
 */
function widthOf(line: string, fontSize: number): number {
	return theme.label.widthPerCharacter * fontSize * line.length;
}
