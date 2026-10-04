/**
 * The drawings that sit on a key, one function each.
 *
 * Every fragment is centred on {@link GLYPH_CENTRE} inside a 72 unit key and carries its
 * own colours, so {@link keySvg} never has to know what it is placing.
 */

import type { Gaze, WindowLayout } from "../bridge/protocol.js";
import { escapeText } from "./escape.js";
import { GLYPH_CENTRE, round, theme } from "./theme.js";

/** "Aa" under a wavy rule: the app's correction. */
export function textCorrect(): string {
	return [
		`<text x="36" y="29" text-anchor="middle" font-family="${theme.fontFamily}" font-size="20" font-weight="700" fill="${theme.ink}">Aa</text>`,
		`<path d="M22,36 q3.5,-4 7,0 t7,0 t7,0 t7,0" fill="none" stroke="${theme.ink}" stroke-width="2.5" stroke-linecap="round"/>`,
	].join("");
}

/** A single chevron: turn this into a prompt. */
export function chevron(): string {
	return `<path d="M29,14 L43,26 L29,38" fill="none" stroke="${theme.ink}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>`;
}

/** Two chevrons: the same, with the expert's hand. */
export function doubleChevron(): string {
	return `<path d="M23,15 L34,26 L23,37 M38,15 L49,26 L38,37" fill="none" stroke="${theme.ink}" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/>`;
}

/** A short word set large, for the language keys. */
export function word(text: string): string {
	return `<text x="36" y="34" text-anchor="middle" font-family="${theme.fontFamily}" font-size="24" font-weight="700" fill="${theme.ink}">${escapeText(text)}</text>`;
}

/** A necktie: the professional tone. */
export function tie(): string {
	return [
		`<path d="M31,11 L41,11 L43,18 L36,22 L29,18 Z" fill="${theme.ink}"/>`,
		`<path d="M33,22 L39,22 L43,34 L36,41 L29,34 Z" fill="${theme.ink}"/>`,
	].join("");
}

/** Lines that shorten as they fall: a text being summarised. */
export function meltingLines(): string {
	const widths = [30, 30, 21, 12];

	return `<g fill="${theme.ink}">${widths
		.map((width, index) => `<rect x="21" y="${13.5 + index * 7.25}" width="${width}" height="3.5" rx="1.75"/>`)
		.join("")}</g>`;
}

/** Nine tiles: the palette of every action. */
export function grid(): string {
	const columns = [22, 32.5, 43];
	const rows = [12, 22.5, 33];

	return `<g fill="${theme.ink}">${rows
		.flatMap((y) => columns.map((x) => `<rect x="${x}" y="${y}" width="7" height="7" rx="1.8"/>`))
		.join("")}</g>`;
}

/** An eighth note — head, stem and flag: what's playing. */
export function musicNote(): string {
	return [
		`<ellipse cx="31" cy="35.4" rx="6.8" ry="5.1" transform="rotate(-20 31 35.4)" fill="${theme.ink}"/>`,
		`<rect x="34.4" y="11" width="3.2" height="23.6" fill="${theme.ink}"/>`,
		`<path d="M37.6,11 C38.4,16.2 43.4,18.2 46.2,21.6 C48.8,24.8 48.4,29.4 45.8,32.6 C46.8,28.6 45.6,25.6 43,23.8 C41.2,22.6 39.2,22 37.6,21.4 Z" fill="${theme.ink}"/>`,
	].join("");
}

/** A microphone on its cradle: dictation. */
export function mic(): string {
	return [
		`<rect x="30" y="11.5" width="12" height="20" rx="6" fill="${theme.ink}"/>`,
		`<path d="M24,27.5 Q36,41.5 48,27.5" fill="none" stroke="${theme.ink}" stroke-width="3" stroke-linecap="round"/>`,
		`<path d="M36,34.5 L36,40.5 M29,40.5 L43,40.5" fill="none" stroke="${theme.ink}" stroke-width="3" stroke-linecap="round"/>`,
	].join("");
}

export type MicOptions = {
	/**
	 * The levels last heard, oldest first, at most seven of them. Giving any array at all —
	 * the empty one included — draws the listening microphone: small, with its meter under
	 * it. Leaving it out draws the resting microphone.
	 */
	levels?: readonly number[];

	/** Draws the padlock of a dictation the user locked hands-free. */
	locked?: boolean;
};

/** How many bars the meter has; the newest level is the rightmost one. */
export const LEVEL_BARS = 7;

/** The meter, in user units: where it sits and how tall a bar grows. */
const METER = { bottom: 42, minHeight: 3.5, maxGrowth: 11.5, barWidth: 3.4, pitch: 5 } as const;

/** How much the microphone shrinks to make room for the meter, and where that leaves it. */
const LISTENING_MIC = { scale: 0.55, top: 9 } as const;

/**
 * The microphone, alone or listening.
 * @param options What the microphone is hearing.
 * @returns The drawing.
 */
export function micGlyph(options: MicOptions = {}): string {
	const { levels, locked = false } = options;
	if (levels === undefined) {
		return mic();
	}

	return [listeningMic(), levelBars(levels), locked ? padlock() : ""].join("");
}

/** The same microphone as at rest, shrunk and raised so the meter fits under it. */
function listeningMic(): string {
	const { scale, top } = LISTENING_MIC;
	// The resting microphone starts at y 11.5; scaling happens about the key's origin.
	const x = GLYPH_CENTRE.x * (1 - scale);
	const y = top - 11.5 * scale;

	return `<g transform="translate(${round(x)} ${round(y)}) scale(${scale})">${mic()}</g>`;
}

/**
 * The meter: one bar per frame kept, the newest on the right.
 *
 * The row is always full — a level that has not arrived yet draws as silence — so the
 * meter reads as a microphone that is listening rather than as one that is filling up.
 * @param levels The levels last heard, oldest first.
 * @returns The drawing.
 */
function levelBars(levels: readonly number[]): string {
	const heard = levels.slice(-LEVEL_BARS);
	const row = [...Array<number>(LEVEL_BARS - heard.length).fill(0), ...heard];
	const { bottom, minHeight, maxGrowth, barWidth, pitch } = METER;
	const left = GLYPH_CENTRE.x - ((LEVEL_BARS - 1) * pitch + barWidth) / 2;

	const bars = row.map((level, index) => {
		const height = minHeight + clamp(level) * maxGrowth;

		return `<rect x="${round(left + index * pitch)}" y="${round(bottom - height)}" width="${barWidth}" height="${round(height)}" rx="${barWidth / 2}"/>`;
	});

	return `<g data-part="levels" fill="${theme.ink}">${bars.join("")}</g>`;
}

/** A closed padlock: the dictation goes on without the key being held. */
function padlock(): string {
	return [
		`<g data-part="lock">`,
		`<path d="M48.5,14 L48.5,11.5 a3,3 0 0 1 6,0 L54.5,14" fill="none" stroke="${theme.ink}" stroke-width="1.8"/>`,
		`<rect x="46" y="14" width="11" height="8.5" rx="2" fill="${theme.ink}"/>`,
		`</g>`,
	].join("");
}

/**
 * Holds a level inside the range the meter draws.
 * @param level Level as the app reported it.
 * @returns The level, between zero and one.
 */
function clamp(level: number): number {
	return Math.min(1, Math.max(0, level));
}

/** Where each layout puts the window inside the screen's usable area. */
const WINDOW_RECTS: Record<Exclude<WindowLayout, "nextScreen">, readonly [number, number, number, number]> = {
	leftHalf: [22, 17, 14, 18],
	rightHalf: [36, 17, 14, 18],
	topHalf: [22, 17, 28, 9],
	bottomHalf: [22, 26, 28, 9],
	topLeft: [22, 17, 14, 9],
	topRight: [36, 17, 14, 9],
	bottomLeft: [22, 26, 14, 9],
	bottomRight: [36, 26, 14, 9],
	maximize: [22, 17, 28, 18],
	center: [27, 21, 18, 10],
};

/** A screen with the window drawn where the layout sends it. */
export function windowLayout(layout: WindowLayout): string {
	const screen = `<rect x="18" y="13" width="36" height="26" rx="3" fill="none" stroke="${theme.dark.frame}" stroke-width="2.5"/>`;

	if (layout === "nextScreen") {
		return [
			screen,
			`<path d="M26,26 L44,26 M37,19 L44,26 L37,33" fill="none" stroke="${theme.dark.window}" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/>`,
		].join("");
	}

	const [x, y, width, height] = WINDOW_RECTS[layout];

	return [screen, `<rect x="${x}" y="${y}" width="${width}" height="${height}" rx="1.5" fill="${theme.dark.window}"/>`].join("");
}

/** An arrow pointing back. */
export function back(): string {
	return `<path d="M44,26 L28,26 M35,19 L28,26 L35,33" fill="none" stroke="${theme.ink}" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/>`;
}

/** A small screen beside a chevron: the door to the windows page. */
export function windowsPage(): string {
	return [
		`<rect x="12" y="15" width="26" height="19" rx="2.5" fill="none" stroke="${theme.ink}" stroke-width="2.5"/>`,
		`<rect x="16.5" y="18.5" width="10" height="12" rx="1.3" fill="${theme.ink}"/>`,
		`<path d="M46,26 L58,26 M52,20 L58,26 L52,32" fill="none" stroke="${theme.ink}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>`,
	].join("");
}

/** An arrow pointing on. */
export function forwardChevron(): string {
	return `<path d="M28,26 L44,26 M37,19 L44,26 L37,33" fill="none" stroke="${theme.ink}" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/>`;
}

/*
 * The mascot, quoted without retouching from `icon/claudio_mascotte.svg` at the root of
 * this repository: the antenna, the head ring, its hollow and the moustache, on the
 * master's 512 grid. The "buste" chassis occupies x 73→440 and y 75→342, so its centre
 * is (256, 208.75); the transform below drops that centre onto the key's glyph centre.
 */

const MASCOT_HEAD_RING =
	"M364.5,182.25l0,102.5c0,28.286 -22.964,51.25 -51.25,51.25l-114.5,0c-28.286,0 -51.25,-22.964 -51.25,-51.25l0,-102.5c0,-28.286 22.964,-51.25 51.25,-51.25l114.5,0c28.286,0 51.25,22.964 51.25,51.25Z M349,189.571l0,87.857c0,24.245 -19.684,43.929 -43.929,43.929l-98.143,0c-24.245,0 -43.929,-19.684 -43.929,-43.929l0,-87.857c0,-24.245 19.684,-43.929 43.929,-43.929l98.143,0c24.245,0 43.929,19.684 43.929,43.929Z";

const MASCOT_HEAD_HOLLOW =
	"M349,189.571l0,87.857c0,24.245 -19.684,43.929 -43.929,43.929l-98.143,0c-24.245,0 -43.929,-19.684 -43.929,-43.929l0,-87.857c0,-24.245 19.684,-43.929 43.929,-43.929l98.143,0c24.245,0 43.929,19.684 43.929,43.929Z";

export const MASCOT_MOUSTACHE =
	"M256,239.765c-26.2,-26.2 -72.05,-22.925 -98.25,6.55c-22.925,26.2 -55.675,32.75 -85.15,16.375c13.1,58.95 62.225,91.7 114.625,75.325c29.475,-9.825 52.4,-32.75 68.775,-58.95c16.375,26.2 39.3,49.125 68.775,58.95c52.4,16.375 101.525,-16.375 114.625,-75.325c-29.475,16.375 -62.225,9.825 -85.15,-16.375c-26.2,-29.475 -72.05,-32.75 -98.25,-6.55Z";

/** Scale that brings the master's 512 grid down to a 27 unit tall mascot. */
const MASCOT_SCALE = 0.101;

/** Centre of the "buste" on the master's grid: x 73→440, y 75→342. */
const MASCOT_ORIGIN = { x: 256, y: 208.75 } as const;

/** The four looks. Nothing else moves between them: that is what holds the character together. */
const MASCOT_EYES: Record<Gaze, string> = {
	// Awake, pupils centred: he is waiting, he is available.
	repos: [
		`<circle cx="219" cy="187.481" r="23.5" fill="${theme.ink}"/>`,
		`<circle cx="293" cy="187.481" r="23.5" fill="${theme.ink}"/>`,
		`<circle cx="219" cy="187.481" r="12.5" fill="${theme.hollow}"/>`,
		`<circle cx="293" cy="187.481" r="12.5" fill="${theme.hollow}"/>`,
	].join(""),
	// Eyes closed: he concentrates while the answer arrives.
	veille: [
		`<rect x="198" y="182" width="42" height="11" rx="5.5" fill="${theme.ink}"/>`,
		`<rect x="272" y="182" width="42" height="11" rx="5.5" fill="${theme.ink}"/>`,
	].join(""),
	// Smiling eyes: the text has landed.
	fait: `<g fill="none" stroke="${theme.ink}" stroke-width="11" stroke-linecap="round"><path d="M199,194 A21,21 0 0 1 239,194"/><path d="M273,194 A21,21 0 0 1 313,194"/></g>`,
	// Full globes, no pupil: he can do nothing — no selection, no key, an error.
	vide: [
		`<circle cx="219" cy="187.481" r="23.5" fill="${theme.ink}"/>`,
		`<circle cx="293" cy="187.481" r="23.5" fill="${theme.ink}"/>`,
	].join(""),
};

/**
 * The mascot, in one of his four looks.
 * @param gaze Look to draw.
 * @returns The drawing.
 */
export function mascot(gaze: Gaze): string {
	const x = GLYPH_CENTRE.x - MASCOT_ORIGIN.x * MASCOT_SCALE;
	const y = GLYPH_CENTRE.y - MASCOT_ORIGIN.y * MASCOT_SCALE;

	return [
		`<g transform="translate(${round(x)} ${round(y)}) scale(${MASCOT_SCALE})">`,
		`<defs><clipPath id="claudio-head"><rect x="120" y="60" width="272" height="211"/></clipPath></defs>`,
		`<rect x="250.5" y="114" width="11" height="23.613" fill="${theme.ink}"/>`,
		`<circle cx="256" cy="96.745" r="21.255" fill="${theme.ink}"/>`,
		`<g clip-path="url(#claudio-head)">`,
		`<path fill-rule="evenodd" d="${MASCOT_HEAD_RING}" fill="${theme.ink}"/>`,
		`<path d="${MASCOT_HEAD_HOLLOW}" fill="${theme.hollow}"/>`,
		`</g>`,
		`<path d="${MASCOT_MOUSTACHE}" fill="${theme.ink}"/>`,
		MASCOT_EYES[gaze],
		`</g>`,
	].join("");
}
