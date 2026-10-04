import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { KeyPainter, PAINT_FLOOR_MS } from "../src/actions/keys.js";
import { SVG_DATA_URI_PREFIX } from "../src/render/uri.js";
import { decodeImage } from "./fakes.js";

/** A key on the hardware, as far as the painter can tell. */
function fakeKey(id = "key-1") {
	const drawnAt: number[] = [];

	return {
		id,
		drawnAt,
		setTitle: vi.fn(async (_title: string) => {}),
		setImage: vi.fn(async (_image: string) => {
			drawnAt.push(Date.now());
		}),
	};
}

/** The drawings the key was actually given, in order, unwrapped from their data URI. */
function drawings(key: ReturnType<typeof fakeKey>): string[] {
	return key.setImage.mock.calls.map((call) => decodeImage(call[0]));
}

describe("KeyPainter", () => {
	let painter: KeyPainter;
	let key: ReturnType<typeof fakeKey>;

	beforeEach(() => {
		vi.useFakeTimers();
		painter = new KeyPainter();
		key = fakeKey();
	});

	afterEach(() => {
		vi.useRealTimers();
	});

	/** Lets the writes in flight finish. */
	async function settle(): Promise<void> {
		await vi.advanceTimersByTimeAsync(0);
	}

	it("draws at once when the key has been still", async () => {
		await painter.paint(key, "<svg>one</svg>");

		expect(drawings(key)).toEqual(["<svg>one</svg>"]);
		// Stream Deck's own title would sit on top of the drawing.
		expect(key.setTitle).toHaveBeenCalledWith("");
	});

	it("hands the key a data URI, not the bare SVG the app would otherwise ignore", async () => {
		await painter.paint(key, "<svg>one</svg>");

		const sent = key.setImage.mock.calls.at(0)![0];
		expect(sent.startsWith(SVG_DATA_URI_PREFIX)).toBe(true);
		expect(decodeImage(sent)).toBe("<svg>one</svg>");
	});

	it("asks for nothing when the key already carries that drawing", async () => {
		await painter.paint(key, "<svg>one</svg>");
		await vi.advanceTimersByTimeAsync(PAINT_FLOOR_MS * 2);

		await painter.paint(key, "<svg>one</svg>");
		await vi.advanceTimersByTimeAsync(PAINT_FLOOR_MS * 2);

		expect(drawings(key)).toEqual(["<svg>one</svg>"]);
	});

	it("holds back a drawing that comes too soon, then draws it", async () => {
		await painter.paint(key, "<svg>one</svg>");

		await painter.paint(key, "<svg>two</svg>");
		expect(drawings(key), "the floor has not passed yet").toEqual(["<svg>one</svg>"]);

		await vi.advanceTimersByTimeAsync(PAINT_FLOOR_MS);

		expect(drawings(key)).toEqual(["<svg>one</svg>", "<svg>two</svg>"]);
	});

	it("drops the drawings in between, and keeps the last one asked for", async () => {
		await painter.paint(key, "<svg>one</svg>");
		await painter.paint(key, "<svg>two</svg>");
		await painter.paint(key, "<svg>three</svg>");
		await painter.paint(key, "<svg>four</svg>");

		await vi.advanceTimersByTimeAsync(PAINT_FLOOR_MS * 3);

		expect(drawings(key)).toEqual(["<svg>one</svg>", "<svg>four</svg>"]);
	});

	it("never draws a key more than ten times in any one second", async () => {
		// The meter at full tilt, then a dictation finishing: far more than ten drawings.
		for (let frame = 0; frame < 13; frame++) {
			await painter.paint(key, `<svg>${frame}</svg>`);
			await vi.advanceTimersByTimeAsync(85);
		}

		await vi.advanceTimersByTimeAsync(PAINT_FLOOR_MS * 3);

		for (const [index, at] of key.drawnAt.entries()) {
			const withinTheSecond = key.drawnAt.slice(index).filter((other) => other - at < 1000);

			expect(withinTheSecond.length, `too many drawings from ${at}`).toBeLessThanOrEqual(10);
		}
		expect(drawings(key).at(-1), "the last drawing asked for is the one on the key").toBe("<svg>12</svg>");
	});

	it("does not believe a drawing the key refused", async () => {
		key.setImage.mockRejectedValueOnce(new Error("the key is gone"));
		await painter.paint(key, "<svg>one</svg>");
		await settle();

		await vi.advanceTimersByTimeAsync(PAINT_FLOOR_MS * 2);
		await painter.paint(key, "<svg>one</svg>");
		await settle();

		expect(drawings(key), "a drawing that never landed has to be sent again").toEqual([
			"<svg>one</svg>",
			"<svg>one</svg>",
		]);
	});

	it("draws one key one drawing at a time, however many redraws are in flight", async () => {
		let land = (): void => {};
		key.setImage.mockImplementationOnce(
			async () =>
				new Promise<void>((resolve) => {
					land = resolve;
				}),
		);

		void painter.paint(key, "<svg>one</svg>");
		await settle();
		await vi.advanceTimersByTimeAsync(PAINT_FLOOR_MS * 2);
		void painter.paint(key, "<svg>two</svg>");
		await vi.advanceTimersByTimeAsync(PAINT_FLOOR_MS * 2);

		expect(drawings(key), "the second waits for the first to land").toEqual(["<svg>one</svg>"]);

		land();
		await settle();

		expect(drawings(key)).toEqual(["<svg>one</svg>", "<svg>two</svg>"]);
	});

	it("keeps every key on its own floor", async () => {
		const other = fakeKey("key-2");

		await painter.paint(key, "<svg>one</svg>");
		await painter.paint(other, "<svg>one</svg>");

		expect(drawings(other), "one key waiting does not hold up another").toEqual(["<svg>one</svg>"]);
	});

	it("draws a key that left the page and came back, at once", async () => {
		await painter.paint(key, "<svg>one</svg>");

		painter.forget(key);
		await painter.paint(key, "<svg>one</svg>");

		expect(drawings(key)).toEqual(["<svg>one</svg>", "<svg>one</svg>"]);
	});

	it("forgets a drawing it was holding for a key that left the page", async () => {
		await painter.paint(key, "<svg>one</svg>");
		await painter.paint(key, "<svg>two</svg>");

		painter.forget(key);
		await vi.advanceTimersByTimeAsync(PAINT_FLOOR_MS * 3);

		expect(drawings(key)).toEqual(["<svg>one</svg>"]);
	});
});
