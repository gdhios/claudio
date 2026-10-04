/**
 * The measurements and colours every key drawing shares.
 *
 * Keys are SVG documents of 72 user units; Stream Deck upsamples them to whatever the
 * hardware asks for, so nothing here is a pixel.
 */

/** Width and height of a key, in user units. */
export const KEY_SIZE = 72;

/** Where a glyph is centred inside a key; the baked label sits under it. */
export const GLYPH_CENTRE = { x: 36, y: 26 } as const;

export const theme = {
	/** Corner radius of the key. */
	radius: 9,

	/** The violet the Claudio keys are cut from, top to bottom. */
	gradient: { top: "#5E35A6", bottom: "#3E106F" },

	/** The darker family the window keys use, so they read as a separate tool. */
	dark: { background: "#120E1C", frame: "#5C5476", window: "#7C4FD0" },

	/** Glyphs are white; the mascot's hollows are the deepest violet of the drawing. */
	ink: "#FFFFFF",
	hollow: "#31104F",

	/** The lighter violet Claudio signs his own name in. */
	accent: "#B08CF0",

	/** A key nobody can press right now. */
	dimmedOpacity: 0.45,

	/** Bold grotesque, whatever the machine has. */
	fontFamily: "'Helvetica Neue', Helvetica, Arial, sans-serif",

	label: {
		/** A line wider than this runs into the rounded corners. */
		maxWidth: 60,
		maxFontSize: 11,
		minFontSize: 7,
		/** Rough width of one character, as a fraction of the font size. */
		widthPerCharacter: 0.58,
		/** Baselines, measured from the top of the key. */
		singleLineBaseline: 63,
		firstLineBaseline: 56,
		secondLineBaseline: 67,
	},
} as const;

/**
 * Trims a computed coordinate to three decimals, so two identical drawings are identical
 * strings — which is what lets a key skip a drawing it already carries.
 * @param value Coordinate to round.
 * @returns The coordinate.
 */
export function round(value: number): number {
	return Math.round(value * 1000) / 1000;
}
