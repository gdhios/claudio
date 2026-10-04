/**
 * Where each deck stands inside the Claudio profile, and how it comes home.
 *
 * The profile has three pages: the face, the actions, the windows. Leaving a deck on the
 * actions is fine for a minute and wrong for an afternoon — the face is what the plugin
 * is for. So the page a deck was sent to is remembered, and a deck left alone on one of
 * the two working pages goes back to the face on its own.
 *
 * Only a page this plugin asked for arms that return. A key of ours can sit on a profile
 * the user built himself, and a press there must never be able to drag his deck onto a
 * profile he did not ask for.
 */

/** Name of the profile shipped with the plugin; the manifest carries the same one. */
export const PROFILE_NAME = "Claudio";

/** The pages of that profile, in the order they are laid out. */
export const PAGES = { face: 0, actions: 1, windows: 2 } as const;

export type PageName = keyof typeof PAGES;

/** Delays the property inspector offers, in seconds; zero means never. */
export const IDLE_SECONDS_CHOICES = [30, 60, 120, 0];

/** How long a deck is left on a working page when nobody has said otherwise. */
export const DEFAULT_IDLE_SECONDS = 60;

/**
 * Asks Stream Deck to show a profile; without a name, the one the user was on before.
 */
export type ProfileSwitch = (deviceId: string, profile?: string, page?: number) => Promise<void>;

/**
 * Reads the delay a face tile carries.
 *
 * The property inspector stores what its select holds, which is text; anything else is a
 * setting from a version that did not have this one.
 * @param value What the tile's settings say.
 * @returns The delay in seconds, zero for never.
 */
export function readIdleSeconds(value: unknown): number {
	const seconds = typeof value === "string" ? Number(value) : value;

	return typeof seconds === "number" && IDLE_SECONDS_CHOICES.includes(seconds) ? seconds : DEFAULT_IDLE_SECONDS;
}

export class IdleReturn {
	readonly #switchProfile: ProfileSwitch;

	/** How long a deck may sit on a working page; `null` when it may sit there forever. */
	#delayMs: number | null = DEFAULT_IDLE_SECONDS * 1000;

	/** The page each deck was last known to be on, by device. */
	readonly #pages = new Map<string, number>();

	/** The return waiting on each deck, by device. */
	readonly #timers = new Map<string, ReturnType<typeof setTimeout>>();

	/**
	 * @param switchProfile How a profile is shown on a deck.
	 */
	public constructor(switchProfile: ProfileSwitch) {
		this.#switchProfile = switchProfile;
	}

	/**
	 * Sets how long a deck may be left on a working page.
	 * @param seconds The delay; zero for never.
	 */
	public setDelay(seconds: number): void {
		this.#delayMs = seconds > 0 ? seconds * 1000 : null;
		for (const deviceId of [...this.#timers.keys()]) {
			this.#arm(deviceId);
		}
	}

	/**
	 * Takes a deck to one of the profile's pages.
	 * @param deviceId The deck.
	 * @param page Page to show.
	 * @returns A promise that settles once Stream Deck has been asked.
	 */
	public async show(deviceId: string, page: PageName): Promise<void> {
		this.#pages.set(deviceId, PAGES[page]);
		this.#arm(deviceId);

		return this.#switchProfile(deviceId, PROFILE_NAME, PAGES[page]);
	}

	/**
	 * Gives a deck back to whatever profile it was showing before.
	 * @param deviceId The deck.
	 * @returns A promise that settles once Stream Deck has been asked.
	 */
	public async leave(deviceId: string): Promise<void> {
		this.#pages.delete(deviceId);
		this.#cancel(deviceId);

		return this.#switchProfile(deviceId);
	}

	/**
	 * Records that the face is on screen, which only page 0 can show.
	 * @param deviceId The deck.
	 */
	public sawFace(deviceId: string): void {
		this.#pages.set(deviceId, PAGES.face);
		this.#cancel(deviceId);
	}

	/**
	 * Puts off the return to the face: a key was just pressed on this deck.
	 * @param deviceId The deck.
	 */
	public touch(deviceId: string): void {
		this.#arm(deviceId);
	}

	/** Forgets every return waiting. */
	public stop(): void {
		for (const deviceId of [...this.#timers.keys()]) {
			this.#cancel(deviceId);
		}
	}

	/**
	 * Starts the wait again for a deck, when there is something to come back from.
	 * @param deviceId The deck.
	 */
	#arm(deviceId: string): void {
		this.#cancel(deviceId);
		const page = this.#pages.get(deviceId);
		if (this.#delayMs === null || page === undefined || page === PAGES.face) {
			return;
		}

		this.#timers.set(
			deviceId,
			setTimeout(() => {
				this.#timers.delete(deviceId);
				void this.show(deviceId, "face");
			}, this.#delayMs),
		);
	}

	/**
	 * Drops the return waiting on a deck, if one is.
	 * @param deviceId The deck.
	 */
	#cancel(deviceId: string): void {
		const timer = this.#timers.get(deviceId);
		if (timer !== undefined) {
			clearTimeout(timer);
			this.#timers.delete(deviceId);
		}
	}
}
