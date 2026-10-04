import { describe, expect, it } from "vitest";

import {
	changedTiles,
	FACE_HEIGHT,
	FACE_WIDTH,
	type FaceParams,
	faceSvg,
	TILE_PITCH,
	tileKey,
	tileSvg,
} from "../src/render/face.js";
import { KEY_SIZE } from "../src/render/theme.js";

/** Claudio at rest, connected, saying nothing. */
const RESTING: FaceParams = { gaze: "repos", level: 0, glow: false, disconnected: false };

/** Every tile of the deck, so a test can say "all of them" without listing them. */
const EVERY_TILE = [0, 1, 2].flatMap((row) => [0, 1, 2, 3, 4].map((column) => tileKey(column, row)));

/**
 * The moustache's transform, as the face writes it.
 * @param face A face drawing.
 * @returns The translate and scale, in the order they appear.
 */
function moustache(face: string): { x: number; y: number; scaleX: number; scaleY: number } {
	const found = /translate\((-?[\d.]+) (-?[\d.]+)\) scale\(([\d.]+) ([\d.]+)\)/.exec(face);
	expect(found, "the face draws no moustache").not.toBeNull();
	const [x, y, scaleX, scaleY] = found!.slice(1).map(Number);

	return { x: x!, y: y!, scaleX: scaleX!, scaleY: scaleY! };
}

describe("faceSvg", () => {
	it("spreads one drawing over the whole deck", () => {
		const face = faceSvg(RESTING);

		expect(FACE_WIDTH).toBe(504);
		expect(FACE_HEIGHT).toBe(288);
		expect(face).toContain(`viewBox="0 0 ${FACE_WIDTH} ${FACE_HEIGHT}"`);
	});

	it("draws the head ring where the mock put it", () => {
		// The top band lands on the first row, the sides on the outer columns, and the
		// bottom of the ring falls off the deck — the head is cut by the edge of the desk.
		expect(faceSvg(RESTING)).toContain(
			'<rect x="20" y="55" width="464" height="380" rx="75" fill="#31104F" stroke="#FFFFFF" stroke-width="30"/>',
		);
	});

	it("stands the antenna over the middle key of the first row", () => {
		const face = faceSvg(RESTING);

		expect(face).toContain('<rect x="249" y="23" width="6" height="20"');
		expect(face).toContain('<circle cx="252" cy="17" r="13"');
	});

	it("lights the antenna only when Claudio is working", () => {
		expect(faceSvg(RESTING)).not.toContain("claudio-face-glow");
		expect(faceSvg({ ...RESTING, glow: true })).toContain("claudio-face-glow");
	});

	it("gives each look its own pair of eyes, and nothing else", () => {
		const looks = (["repos", "veille", "fait", "vide"] as const).map((gaze) => faceSvg({ ...RESTING, gaze }));

		expect(new Set(looks).size, "two looks draw the same face").toBe(4);
		// Pupils only when he is looking at you; closed bars when he blinks.
		expect(looks[0]).toContain('<circle cx="144" cy="144" r="15"');
		expect(looks[1]).toContain('<rect x="117" y="137" width="54" height="14" rx="7"');
		expect(looks[3]).not.toContain('r="15"');
	});

	it("raises the moustache as the voice rises", () => {
		const quiet = moustache(faceSvg(RESTING));
		const loud = moustache(faceSvg({ ...RESTING, level: 1 }));

		expect(loud.y, "the dip of the moustache should climb").toBeLessThan(quiet.y);
		expect(loud.scaleY, "the moustache should swell").toBeGreaterThan(quiet.scaleY);
		expect(loud.scaleX, "only its height answers the voice").toBe(quiet.scaleX);
	});

	it("asks the user to open Claudio when nobody answers", () => {
		const face = faceSvg({ ...RESTING, gaze: "repos", glow: true, disconnected: true, message: "Ouvrir Claudio" });

		expect(face).toContain(">Ouvrir<");
		expect(face).toContain(">Claudio<");
		// Nothing is happening behind a connection that is gone: empty eyes, dark antenna.
		expect(face).not.toContain("claudio-face-glow");
		expect(face).not.toContain('r="15"');
		expect(face).toContain('opacity="0.45"');
	});

	it("keeps a stray ampersand from breaking the drawing", () => {
		expect(faceSvg({ ...RESTING, disconnected: true, message: "A & B" })).toContain("&amp;");
	});
});

describe("tileSvg", () => {
	it("gives each key its own window onto the face", () => {
		const face = faceSvg(RESTING);

		for (const row of [0, 1, 2]) {
			for (const column of [0, 1, 2, 3, 4]) {
				const tile = tileSvg(face, column, row);

				expect(tile).toContain(
					`viewBox="${column * TILE_PITCH} ${row * TILE_PITCH} ${KEY_SIZE} ${KEY_SIZE}"`,
				);
				expect(tile).toContain(`width="${KEY_SIZE}" height="${KEY_SIZE}"`);
			}
		}
	});

	it("carries the whole drawing, definitions and all, so the colours resolve", () => {
		const tile = tileSvg(faceSvg(RESTING), 3, 1);

		expect(tile).toContain("claudio-face-sky");
		expect(tile).toContain('<circle cx="360" cy="144" r="29"');
		expect(tile.startsWith("<svg")).toBe(true);
		expect(tile.endsWith("</svg>")).toBe(true);
	});

	it("leaves the keys their gutter: the tiles do not touch", () => {
		expect(TILE_PITCH).toBe(KEY_SIZE + 36);
	});
});

describe("changedTiles", () => {
	it("redraws nothing when nothing moved", () => {
		expect(changedTiles(RESTING, { ...RESTING })).toEqual(new Set());
	});

	it("redraws the two eyes when he blinks", () => {
		expect(changedTiles(RESTING, { ...RESTING, gaze: "veille" })).toEqual(new Set(["1,1", "3,1"]));
	});

	it("redraws the antenna alone when it lights up", () => {
		expect(changedTiles(RESTING, { ...RESTING, glow: true })).toEqual(new Set(["2,0"]));
	});

	it("redraws the bottom row alone when the voice moves the moustache", () => {
		expect(changedTiles(RESTING, { ...RESTING, level: 0.6 })).toEqual(
			new Set(["0,2", "1,2", "2,2", "3,2", "4,2"]),
		);
	});

	it("redraws the middle key when the message changes", () => {
		const asking: FaceParams = { ...RESTING, disconnected: true, message: "Ouvrir Claudio" };

		expect(changedTiles(asking, { ...asking, message: "Open Claudio" })).toEqual(new Set(["2,1"]));
	});

	it("redraws everything when the connection comes or goes", () => {
		expect(changedTiles(RESTING, { ...RESTING, disconnected: true })).toEqual(new Set(EVERY_TILE));
		expect(changedTiles({ ...RESTING, disconnected: true }, RESTING)).toEqual(new Set(EVERY_TILE));
	});

	it("ignores what a face that lost its connection no longer shows", () => {
		const gone: FaceParams = { gaze: "repos", level: 0, glow: false, disconnected: true, message: "Ouvrir" };

		// Empty eyes and a dark antenna either way: neither key is worth sending again.
		expect(changedTiles(gone, { ...gone, gaze: "fait", glow: true })).toEqual(new Set());
	});
});
