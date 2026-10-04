import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
	DEFAULT_IDLE_SECONDS,
	IDLE_SECONDS_CHOICES,
	IdleReturn,
	PAGES,
	PROFILE_NAME,
	readIdleSeconds,
} from "../src/idle.js";

const RED = "deck-red";
const BLUE = "deck-blue";

/**
 * Stream Deck showing a profile, as far as the return can tell.
 * @returns The stand-in.
 */
function fakeSwitch() {
	return vi.fn(async (_deviceId: string, _profile?: string, _page?: number) => {});
}

describe("IdleReturn", () => {
	let switchProfile: ReturnType<typeof fakeSwitch>;
	let idle: IdleReturn;

	beforeEach(() => {
		vi.useFakeTimers();
		switchProfile = fakeSwitch();
		idle = new IdleReturn(switchProfile);
	});

	afterEach(() => {
		idle.stop();
		vi.useRealTimers();
	});

	/** Lets the whole delay pass, and then some. */
	async function waited(seconds = DEFAULT_IDLE_SECONDS): Promise<void> {
		await vi.advanceTimersByTimeAsync(seconds * 1000 + 100);
	}

	it("names the three pages of the profile it ships", () => {
		expect(PROFILE_NAME).toBe("Claudio");
		expect(PAGES).toEqual({ face: 0, actions: 1, windows: 2 });
	});

	it("takes a deck to the page that was asked for", async () => {
		await idle.show(RED, "actions");
		await idle.show(RED, "windows");
		await idle.show(RED, "face");

		expect(switchProfile.mock.calls).toEqual([
			[RED, PROFILE_NAME, 1],
			[RED, PROFILE_NAME, 2],
			[RED, PROFILE_NAME, 0],
		]);
	});

	it("gives a deck back to whatever it was showing before", async () => {
		await idle.leave(RED);

		// No profile named: Stream Deck returns to the one the user was on.
		expect(switchProfile).toHaveBeenCalledWith(RED);
		expect(switchProfile.mock.calls[0]).toHaveLength(1);
	});

	it("comes home to the face once the deck has been left alone", async () => {
		await idle.show(RED, "actions");
		switchProfile.mockClear();

		await waited();

		expect(switchProfile).toHaveBeenCalledOnce();
		expect(switchProfile).toHaveBeenCalledWith(RED, PROFILE_NAME, PAGES.face);
	});

	it("comes home only once, and then stays there", async () => {
		await idle.show(RED, "windows");
		switchProfile.mockClear();

		await waited();
		await waited();

		expect(switchProfile).toHaveBeenCalledOnce();
	});

	it("puts the return off for as long as keys are being pressed", async () => {
		await idle.show(RED, "actions");
		switchProfile.mockClear();

		await vi.advanceTimersByTimeAsync(DEFAULT_IDLE_SECONDS * 1000 - 500);
		idle.touch(RED);
		await vi.advanceTimersByTimeAsync(DEFAULT_IDLE_SECONDS * 1000 - 500);

		expect(switchProfile).not.toHaveBeenCalled();

		await waited();

		expect(switchProfile).toHaveBeenCalledWith(RED, PROFILE_NAME, PAGES.face);
	});

	it("stays where it is when a key is pressed on a deck it never sent anywhere", async () => {
		// The key could be on a profile of the user's own: nothing gives us the right to
		// take his deck somewhere he never asked to go.
		idle.touch(RED);

		await waited();

		expect(switchProfile).not.toHaveBeenCalled();
	});

	it("has nowhere to come home from once the face is on screen", async () => {
		await idle.show(RED, "actions");
		idle.sawFace(RED);
		switchProfile.mockClear();

		await waited();

		expect(switchProfile).not.toHaveBeenCalled();
	});

	it("lets a deck that left the profile go", async () => {
		await idle.show(RED, "actions");
		await idle.leave(RED);
		switchProfile.mockClear();

		await waited();

		expect(switchProfile).not.toHaveBeenCalled();
	});

	it("never comes home when the user asked for never", async () => {
		idle.setDelay(0);
		await idle.show(RED, "actions");
		switchProfile.mockClear();

		await waited(600);

		expect(switchProfile).not.toHaveBeenCalled();
	});

	it("drops a return that is already waiting when the user asks for never", async () => {
		await idle.show(RED, "actions");
		switchProfile.mockClear();

		idle.setDelay(0);
		await waited();

		expect(switchProfile).not.toHaveBeenCalled();
	});

	it("counts the delay the user chose", async () => {
		idle.setDelay(30);
		await idle.show(RED, "actions");
		switchProfile.mockClear();

		await vi.advanceTimersByTimeAsync(29_000);

		expect(switchProfile).not.toHaveBeenCalled();

		await waited(30);

		expect(switchProfile).toHaveBeenCalledWith(RED, PROFILE_NAME, PAGES.face);
	});

	it("keeps each deck's page and each deck's clock to itself", async () => {
		await idle.show(RED, "actions");
		await vi.advanceTimersByTimeAsync(30_000);
		await idle.show(BLUE, "windows");
		switchProfile.mockClear();

		await vi.advanceTimersByTimeAsync(31_000);

		// The red deck's delay ran out; the blue one still has half of it left.
		expect(switchProfile.mock.calls).toEqual([[RED, PROFILE_NAME, PAGES.face]]);

		await waited();

		expect(switchProfile).toHaveBeenCalledWith(BLUE, PROFILE_NAME, PAGES.face);
	});

	it("forgets every clock when the plugin goes", async () => {
		await idle.show(RED, "actions");
		switchProfile.mockClear();

		idle.stop();
		await waited();

		expect(switchProfile).not.toHaveBeenCalled();
	});
});

describe("readIdleSeconds", () => {
	it("offers the delays the inspector lists, and rests on a minute", () => {
		expect(IDLE_SECONDS_CHOICES).toEqual([30, 60, 120, 0]);
		expect(DEFAULT_IDLE_SECONDS).toBe(60);
	});

	it("reads what the property inspector stored, string or number", () => {
		expect(readIdleSeconds(30)).toBe(30);
		// A select stores its value as text, and the delay has to survive that.
		expect(readIdleSeconds("120")).toBe(120);
		expect(readIdleSeconds("0")).toBe(0);
	});

	it("falls back on the minute when the settings say nothing it knows", () => {
		expect(readIdleSeconds(undefined)).toBe(DEFAULT_IDLE_SECONDS);
		expect(readIdleSeconds("soon")).toBe(DEFAULT_IDLE_SECONDS);
		expect(readIdleSeconds(45)).toBe(DEFAULT_IDLE_SECONDS);
	});
});
