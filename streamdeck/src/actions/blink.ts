/**
 * What makes the mascot look alive when nothing at all is happening.
 *
 * A face that never moves reads as a picture; a face that blinks reads as somebody
 * waiting. So the eyes close for a moment every few seconds, at a pace that is never
 * quite the same twice — a regular blink would read as a machine.
 *
 * He only blinks when he has nothing better to do with his eyes: a look the app is
 * wearing on purpose is not something to interrupt.
 */

/** The shortest and the longest wait between two blinks. */
export const BLINK_MIN_MS = 4000;
export const BLINK_MAX_MS = 7000;

/** How long the eyes stay closed. */
export const BLINK_CLOSED_MS = 120;

export class Blink {
	readonly #redraw: () => void;
	readonly #random: () => number;

	/** Whether the eyes are closed right now. */
	#closed = false;

	/** The next thing due — a blink, or its end; `null` when he is not blinking. */
	#timer: ReturnType<typeof setTimeout> | null = null;

	/**
	 * @param redraw Called whenever the eyes open or close.
	 * @param random Where the pace comes from; injected so a test can pin it down.
	 */
	public constructor(redraw: () => void, random: () => number = Math.random) {
		this.#redraw = redraw;
		this.#random = random;
	}

	/**
	 * Whether the eyes are closed right now.
	 * @returns `true` while they are.
	 */
	public get closed(): boolean {
		return this.#closed;
	}

	/**
	 * Says whether he may blink at all, without disturbing a blink already under way.
	 * @param allowed Whether the eyes are his to close.
	 */
	public follow(allowed: boolean): void {
		if (!allowed) {
			this.stop();

			return;
		}

		if (this.#timer === null) {
			this.#wait();
		}
	}

	/** Stops blinking, and opens the eyes if they were shut. */
	public stop(): void {
		if (this.#timer !== null) {
			clearTimeout(this.#timer);
			this.#timer = null;
		}

		if (this.#closed) {
			this.#closed = false;
			this.#redraw();
		}
	}

	/** Waits out the pause before the next blink. */
	#wait(): void {
		const pause = BLINK_MIN_MS + this.#random() * (BLINK_MAX_MS - BLINK_MIN_MS);
		this.#timer = setTimeout(() => this.#close(), pause);
	}

	/** Closes the eyes, and lines up their opening. */
	#close(): void {
		this.#closed = true;
		this.#timer = setTimeout(() => this.#open(), BLINK_CLOSED_MS);
		this.#redraw();
	}

	/** Opens the eyes, and lines up the next blink. */
	#open(): void {
		this.#closed = false;
		this.#wait();
		this.#redraw();
	}
}
