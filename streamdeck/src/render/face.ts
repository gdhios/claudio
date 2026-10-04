/**
 * Claudio's face, spread over the fifteen keys of a deck.
 *
 * One drawing, 504 by 288 user units, of which each key shows a 72 unit window: the keys
 * sit 36 units apart on the hardware, and the gutters are drawn and then thrown away, so
 * the eyes land in the middle row and the moustache along the bottom one. The head is
 * taller than the deck — the ring runs off the bottom edge, as a face too close to the
 * camera does.
 *
 * Everything here is a pure function of what the app is doing: no key, no timer, no
 * Stream Deck.
 */

import type { Gaze } from "../bridge/protocol.js";
import { escapeText } from "./escape.js";
import { bakeLabel } from "./key.js";
import { MASCOT_MOUSTACHE } from "./glyphs.js";
import { KEY_SIZE, round, theme } from "./theme.js";

/** Keys across, and keys down, of the deck the face is drawn for. */
export const FACE_COLUMNS = 5;
export const FACE_ROWS = 3;

/** From one key to the next: the key itself, plus the gutter between two of them. */
export const TILE_PITCH = KEY_SIZE + 36;

/** The whole canvas: every key, and every gutter but the outer ones. */
export const FACE_WIDTH = FACE_COLUMNS * TILE_PITCH - (TILE_PITCH - KEY_SIZE);
export const FACE_HEIGHT = FACE_ROWS * TILE_PITCH - (TILE_PITCH - KEY_SIZE);

export type FaceParams = {
	/** Which pair of eyes he wears. */
	gaze: Gaze;

	/** How loud the voice is, between zero and one; it swells the moustache. */
	level: number;

	/** Whether the antenna is lit, because Claudio is working. */
	glow: boolean;

	/** Whether nobody answers: empty eyes, no glow, and the message below. */
	disconnected: boolean;

	/** What to write across the middle key while nobody answers. */
	message?: string;
};

/** The colours of the face, which is a scene rather than a key. */
const FACE = { skyTop: "#22123E", skyBottom: "#0E081A", glow: "#7C4FD0" } as const;

/** The head ring, whose bottom falls off the canvas on purpose. */
const RING = { x: 20, y: 55, width: 464, height: 380, radius: 75, stroke: 30 } as const;

/** The antenna, over the middle key of the first row. */
const ANTENNA = {
	x: FACE_WIDTH / 2,
	stemY: 23,
	stemWidth: 6,
	stemHeight: 20,
	ballY: 17,
	ballRadius: 13,
	glowRadius: 45,
} as const;

/** The eyes, on the middle row: one on the second key, one on the fourth. */
const EYE = { left: 144, right: 360, y: 144, white: 29, pupil: 15 } as const;

/**
 * The moustache: the mascot's own path, flattened and stretched across the deck.
 *
 * `dip` is the point of the path that sits at the middle of the moustache; putting it
 * where the drawing wants it is what the transform does. The voice lifts that dip and
 * swells the curve under it, which is the whole animation.
 */
const MOUSTACHE = {
	span: 470,
	pathWidth: 366.8,
	dip: { x: 256, y: 239.765 },
	flat: 0.55,
	swell: 0.35,
	restY: 218,
	lift: 15,
} as const;

/** Where the message is written while nobody answers: the middle key of the middle row. */
const MESSAGE = { x: FACE_WIDTH / 2, y: EYE.y, lineSpacing: 1.25, capHeight: 0.35 } as const;

/** What the face actually shows, once a lost connection has had its say. */
type ShownFace = {
	gaze: Gaze;
	level: number;
	glow: boolean;
	message: string;
	disconnected: boolean;
};

/**
 * Draws the whole face.
 * @param params What Claudio is doing.
 * @returns The SVG document, 504 by 288 user units.
 */
export function faceSvg(params: FaceParams): string {
	return `${faceOpenTag()}${faceBody(shown(params))}</svg>`;
}

/**
 * Cuts one key's window out of a face.
 *
 * The whole drawing goes into every tile, definitions and all — the key only shows the
 * part its `viewBox` frames, and a gradient whose definition stayed behind would resolve
 * to nothing.
 * @param face A drawing from {@link faceSvg}.
 * @param column Column of the key, from the left.
 * @param row Row of the key, from the top.
 * @returns The SVG document for that key.
 */
export function tileSvg(face: string, column: number, row: number): string {
	const body = face.slice(face.indexOf(">") + 1, face.lastIndexOf("</svg>"));

	return [
		`<svg xmlns="http://www.w3.org/2000/svg"`,
		` viewBox="${column * TILE_PITCH} ${row * TILE_PITCH} ${KEY_SIZE} ${KEY_SIZE}"`,
		` width="${KEY_SIZE}" height="${KEY_SIZE}">${body}</svg>`,
	].join("");
}

/**
 * Names a tile the way the board keys them.
 * @param column Column of the key, from the left.
 * @param row Row of the key, from the top.
 * @returns The name.
 */
export function tileKey(column: number, row: number): string {
	return `${column},${row}`;
}

/**
 * Which keys differ between two faces.
 *
 * Drawn structurally rather than by comparing images: each part of the face is known to
 * live on certain keys, so a blink costs two drawings and a syllable costs five, instead
 * of fifteen apiece.
 * @param previous The face on the deck now.
 * @param next The face asked for.
 * @returns The names of the keys to redraw.
 */
export function changedTiles(previous: FaceParams, next: FaceParams): Set<string> {
	const before = shown(previous);
	const after = shown(next);
	if (before.disconnected !== after.disconnected) {
		return everyTile();
	}

	const changed = new Set<string>();
	if (before.gaze !== after.gaze) {
		changed.add(tileKey(1, 1));
		changed.add(tileKey(3, 1));
	}

	if (before.glow !== after.glow) {
		changed.add(tileKey(2, 0));
	}

	if (before.level !== after.level) {
		for (let column = 0; column < FACE_COLUMNS; column++) {
			changed.add(tileKey(column, FACE_ROWS - 1));
		}
	}

	if (before.message !== after.message) {
		changed.add(tileKey(2, 1));
	}

	return changed;
}

/**
 * Every key of the deck.
 * @returns Their names.
 */
function everyTile(): Set<string> {
	const tiles = new Set<string>();
	for (let row = 0; row < FACE_ROWS; row++) {
		for (let column = 0; column < FACE_COLUMNS; column++) {
			tiles.add(tileKey(column, row));
		}
	}

	return tiles;
}

/**
 * What a face shows, once a lost connection has taken what it takes.
 *
 * A connection that is gone leaves nothing to animate: the eyes empty, the antenna goes
 * dark, and the only thing left to say is how to bring Claudio back.
 * @param params What Claudio is doing.
 * @returns What the drawing carries.
 */
function shown(params: FaceParams): ShownFace {
	const { gaze, level, glow, disconnected, message = "" } = params;

	return disconnected
		? { gaze: "vide", level, glow: false, message, disconnected: true }
		: { gaze, level, glow, message: "", disconnected: false };
}

/**
 * The opening tag of the whole canvas.
 * @returns The tag.
 */
function faceOpenTag(): string {
	return [
		`<svg xmlns="http://www.w3.org/2000/svg"`,
		` viewBox="0 0 ${FACE_WIDTH} ${FACE_HEIGHT}"`,
		` width="${FACE_WIDTH}" height="${FACE_HEIGHT}">`,
	].join("");
}

/**
 * Everything inside the canvas.
 * @param face What the drawing carries.
 * @returns The markup.
 */
function faceBody(face: ShownFace): string {
	const dimmed = face.disconnected ? ` opacity="${theme.dimmedOpacity}"` : "";

	return [
		definitions(face.glow),
		`<g${dimmed}>`,
		`<rect x="0" y="0" width="${FACE_WIDTH}" height="${FACE_HEIGHT}" fill="url(#claudio-face-sky)"/>`,
		ring(),
		face.glow ? glow() : "",
		antenna(),
		moustache(face.level),
		eyes(face.gaze),
		face.message === "" ? "" : message(face.message),
		`</g>`,
	].join("");
}

/**
 * The gradients the face is painted with.
 * @param lit Whether the antenna's halo is needed.
 * @returns The definitions.
 */
function definitions(lit: boolean): string {
	const halo = lit
		? [
				`<radialGradient id="claudio-face-glow">`,
				`<stop offset="0" stop-color="${FACE.glow}" stop-opacity="0.85"/>`,
				`<stop offset="1" stop-color="${FACE.glow}" stop-opacity="0"/>`,
				`</radialGradient>`,
			].join("")
		: "";

	return [
		`<defs><linearGradient id="claudio-face-sky" x1="0" y1="0" x2="0" y2="1">`,
		`<stop offset="0" stop-color="${FACE.skyTop}"/>`,
		`<stop offset="1" stop-color="${FACE.skyBottom}"/>`,
		`</linearGradient>${halo}</defs>`,
	].join("");
}

/**
 * The head ring, whose white band runs along the top row and down the outer columns.
 * @returns The drawing.
 */
function ring(): string {
	return [
		`<rect x="${RING.x}" y="${RING.y}" width="${RING.width}" height="${RING.height}" rx="${RING.radius}"`,
		` fill="${theme.hollow}" stroke="${theme.ink}" stroke-width="${RING.stroke}"/>`,
	].join("");
}

/**
 * The halo behind the antenna's ball, while Claudio is working.
 * @returns The drawing.
 */
function glow(): string {
	return `<circle cx="${ANTENNA.x}" cy="${ANTENNA.ballY}" r="${ANTENNA.glowRadius}" fill="url(#claudio-face-glow)"/>`;
}

/**
 * The antenna: a stem and its ball.
 * @returns The drawing.
 */
function antenna(): string {
	return [
		`<rect x="${ANTENNA.x - ANTENNA.stemWidth / 2}" y="${ANTENNA.stemY}"`,
		` width="${ANTENNA.stemWidth}" height="${ANTENNA.stemHeight}" fill="${theme.ink}"/>`,
		`<circle cx="${ANTENNA.x}" cy="${ANTENNA.ballY}" r="${ANTENNA.ballRadius}" fill="${theme.ink}"/>`,
	].join("");
}

/**
 * The moustache, lifted and swollen by the voice.
 * @param level How loud the voice is, between zero and one.
 * @returns The drawing.
 */
function moustache(level: number): string {
	const loudness = Math.min(1, Math.max(0, level));
	const scaleX = MOUSTACHE.span / MOUSTACHE.pathWidth;
	const scaleY = scaleX * MOUSTACHE.flat * (1 + MOUSTACHE.swell * loudness);
	const dipY = MOUSTACHE.restY - MOUSTACHE.lift * loudness;
	const x = FACE_WIDTH / 2 - MOUSTACHE.dip.x * scaleX;
	const y = dipY - MOUSTACHE.dip.y * scaleY;

	return [
		`<path transform="translate(${round(x)} ${round(y)}) scale(${round(scaleX)} ${round(scaleY)})"`,
		` d="${MASCOT_MOUSTACHE}" fill="${theme.ink}"/>`,
	].join("");
}

/**
 * The eyes, in one of the four looks.
 * @param gaze Look to draw.
 * @returns The drawing.
 */
function eyes(gaze: Gaze): string {
	const centres = [EYE.left, EYE.right];
	switch (gaze) {
		case "veille":
			// Closed: two bars, as wide as the whites they cover.
			return centres
				.map(
					(x) =>
						`<rect x="${x - 27}" y="${EYE.y - 7}" width="54" height="14" rx="7" fill="${theme.ink}"/>`,
				)
				.join("");
		case "fait":
			// Smiling: the text has landed.
			return [
				`<g fill="none" stroke="${theme.ink}" stroke-width="14" stroke-linecap="round">`,
				centres.map((x) => `<path d="M${x - 27},151 A26,26 0 0 1 ${x + 27},151"/>`).join(""),
				`</g>`,
			].join("");
		default: {
			const whites = centres
				.map((x) => `<circle cx="${x}" cy="${EYE.y}" r="${EYE.white}" fill="${theme.ink}"/>`)
				.join("");
			if (gaze === "vide") {
				// Full globes, no pupil: there is nothing behind them.
				return whites;
			}

			return [
				whites,
				centres
					.map((x) => `<circle cx="${x}" cy="${EYE.y}" r="${EYE.pupil}" fill="${theme.hollow}"/>`)
					.join(""),
			].join("");
		}
	}
}

/**
 * The message written inside the ring, on the middle key.
 *
 * Baked the way a key label is, so it breaks and shrinks to stay on its own key rather
 * than running across the two eyes.
 * @param text What to say.
 * @returns The drawing.
 */
function message(text: string): string {
	const { lines, fontSize } = bakeLabel(text);
	const spacing = fontSize * MESSAGE.lineSpacing;
	const first = MESSAGE.y - ((lines.length - 1) * spacing) / 2 + fontSize * MESSAGE.capHeight;

	return lines
		.map(
			(line, index) =>
				[
					`<text x="${MESSAGE.x}" y="${round(first + index * spacing)}" text-anchor="middle"`,
					` font-family="${theme.fontFamily}" font-size="${fontSize}" font-weight="700"`,
					` fill="${theme.ink}">${escapeText(line)}</text>`,
				].join(""),
		)
		.join("");
}
