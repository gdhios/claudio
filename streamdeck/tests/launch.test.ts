import { beforeEach, describe, expect, it, vi } from "vitest";

const openUrl = vi.fn<(url: string) => Promise<void>>();
const logError = vi.fn();
const spawn = vi.fn(() => ({ on: vi.fn(), unref: vi.fn() }));

vi.mock("@elgato/streamdeck", () => ({
	default: {
		system: { openUrl: (url: string) => openUrl(url) },
		logger: { error: (...args: unknown[]) => logError(...args) },
	},
}));

vi.mock("node:child_process", () => ({
	spawn: (...args: unknown[]) => spawn(...(args as [])),
}));

const { CLAUDIO_BUNDLE_ID, SETTINGS_URL, tryOpenClaudio } = await import("../src/launch.js");

describe("tryOpenClaudio", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		openUrl.mockResolvedValue();
	});

	it("goes straight to the Stream Deck settings, which also starts the app", async () => {
		await tryOpenClaudio();

		expect(openUrl).toHaveBeenCalledWith("claudio://settings/streamdeck");
		expect(SETTINGS_URL).toBe("claudio://settings/streamdeck");
		expect(spawn).not.toHaveBeenCalled();
	});

	it("falls back to starting the app when the deep link does not take", async () => {
		openUrl.mockRejectedValue(new Error("no handler for claudio://"));

		await tryOpenClaudio();

		expect(spawn).toHaveBeenCalledWith("open", ["-b", CLAUDIO_BUNDLE_ID], expect.anything());
		expect(logError).toHaveBeenCalled();
	});

	it("says so rather than throwing when it cannot start the app either", async () => {
		openUrl.mockRejectedValue(new Error("no handler for claudio://"));
		spawn.mockImplementationOnce(() => {
			throw new Error("open is missing");
		});

		await expect(tryOpenClaudio()).resolves.toBeUndefined();
		expect(logError).toHaveBeenCalledTimes(2);
	});
});
