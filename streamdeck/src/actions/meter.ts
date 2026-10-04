/**
 * The levels a key shows, and how often it may show them.
 *
 * The app sends the loudness eight times a second; Stream Deck accepts ten images a
 * second on one key, and a mouth is not worth ten. So the first level of a burst is drawn
 * at once — the meter has to answer the voice — and everything that follows within the
 * window is drawn as one, when the window closes.
 */

import { LEVEL_BARS } from "../render/glyphs.js";

/** How long a key holds still after drawing its meter. */
export const METER_WINDOW_MS = 125;

export class LevelMeter {
	readonly #redraw: () => void;

	/** The levels last heard, oldest first. */
	#levels: number[] = [];

	/** Runs while no redraw may go out; `null` when one may. */
	#window: ReturnType<typeof setTimeout> | null = null;

	/** Whether a level arrived while that window was open. */
	#pending = false;

	/**
	 * @param redraw Called when the meter has something new to show.
	 */
	public constructor(redraw: () => void) {
		this.#redraw = redraw;
	}

	/**
	 * The levels to draw, oldest first.
	 * @returns The levels.
	 */
	public get levels(): readonly number[] {
		return this.#levels;
	}

	/**
	 * Takes in a level from the app.
	 * @param value The level, between zero and one.
	 */
	public hear(value: number): void {
		this.#levels = [...this.#levels, value].slice(-LEVEL_BARS);
		if (this.#window !== null) {
			this.#pending = true;
			return;
		}

		this.#open();
		this.#redraw();
	}

	/** Forgets everything heard, so the next dictation starts on silence. */
	public forget(): void {
		this.#levels = [];
		this.#pending = false;
		if (this.#window !== null) {
			clearTimeout(this.#window);
			this.#window = null;
		}
	}

	/** Holds the meter still for a moment, then draws whatever arrived meanwhile — once. */
	#open(): void {
		this.#window = setTimeout(() => {
			this.#window = null;
			if (!this.#pending) {
				return;
			}

			this.#pending = false;
			this.#open();
			this.#redraw();
		}, METER_WINDOW_MS);
	}
}
