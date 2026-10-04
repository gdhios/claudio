/**
 * What to do when a key is pressed and nothing answers.
 *
 * Two causes, and only one of them is "Claudio is not running": the other is Claudio
 * running with its bridge switched off, which is what a fresh install looks like. The
 * deep link covers both — macOS starts the app to handle a URL scheme it registered — and
 * it lands on the switch the user actually needs. Starting the app by its bundle
 * identifier is the fallback, for when nothing answers the link at all.
 */

import streamDeck from "@elgato/streamdeck";
import { spawn } from "node:child_process";

/** Claudio's bundle identifier. */
export const CLAUDIO_BUNDLE_ID = "com.guillaumedhios.claudio";

/** Deep link to the Stream Deck section of Claudio's settings. */
export const SETTINGS_URL = "claudio://settings/streamdeck";

/**
 * Takes the user to Claudio's Stream Deck settings, starting the app if it takes that.
 * @returns A promise that settles once one of the two has been attempted.
 */
export async function tryOpenClaudio(): Promise<void> {
	try {
		await streamDeck.system.openUrl(SETTINGS_URL);
	} catch (error) {
		streamDeck.logger.error("Could not open Claudio's Stream Deck settings", error);
		startClaudio();
	}
}

/** Starts Claudio, for when nothing answered its URL scheme. */
function startClaudio(): void {
	try {
		const child = spawn("open", ["-b", CLAUDIO_BUNDLE_ID], { detached: true, stdio: "ignore" });
		child.on("error", (error) => streamDeck.logger.error("Failed to start Claudio", error));
		child.unref();
	} catch (error) {
		streamDeck.logger.error("Failed to start Claudio", error);
	}
}
