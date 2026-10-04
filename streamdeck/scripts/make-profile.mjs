/**
 * Writes the bundled Stream Deck profile: the face across page 0, Claudio's actions on
 * page 1, the window layouts on page 2. `npm run profile` regenerates it; the file it
 * writes is committed, since Stream Deck imports it as-is — there is nothing to build
 * from it at install time.
 *
 * Every folder name below is a fresh UUID on every run: Stream Deck tells a profile's
 * pages apart by those, not by anything readable, so re-running this script always
 * produces a byte-different, functionally identical file. This script is standalone
 * JavaScript, not bundled TypeScript, so it repeats the few identifiers it needs from
 * `src/` (action ids, window layouts, page order) rather than importing them.
 */

import { randomUUID } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import JSZip from "jszip";

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const DEFAULT_DESTINATION = path.join(ROOT, "com.okonoma.claudio.sdPlugin", "Claudio.streamDeckProfile");

const PROFILE_NAME = "Claudio";

const FACE_UUID = "com.okonoma.claudio.face";
const ACTION_UUID = "com.okonoma.claudio.action";
const DICTATE_UUID = "com.okonoma.claudio.dictate";
const WINDOW_UUID = "com.okonoma.claudio.window";
const NAVIGATE_UUID = "com.okonoma.claudio.navigate";
const HOTKEY_UUID = "com.elgato.streamdeck.system.hotkey";
/** Stream Deck MK.2, the 5×3 deck the face is drawn for. */
const DEVICE_MODEL = "20GAA9901";

/**
 * One key's worth of settings at one of a page's fifteen coordinates.
 * @param uuid The action's UUID.
 * @param settings Its settings, as `didReceiveSettings` would hand them back.
 * @param name A short, human-readable name for the Stream Deck app's own bookkeeping.
 * @returns The action entry Stream Deck expects in a page's manifest.
 */
function tile(uuid, settings, name) {
	return {
		Name: name,
		Settings: settings,
		State: 0,
		States: [{ Image: "", Title: "", ShowTitle: false }],
		UUID: uuid,
	};
}

/**
 * A bare key press, no modifier held — the `Settings.Hotkeys` shape mirrors an installed
 * Stream Deck profile's own `com.elgato.streamdeck.system.hotkey` entry: two slots, the
 * key itself and an always-present, always-unused second slot.
 * @param code The key's native and virtual code (Return 36, Escape 53 — they agree here).
 * @param qtCode The same key's Qt key code, which Stream Deck also stores.
 * @returns The hotkey action's settings.
 */
function bareKey(code, qtCode) {
	const noModifiers = { KeyCmd: false, KeyCtrl: false, KeyModifiers: 0, KeyOption: false, KeyShift: false };
	return {
		Hotkeys: [
			{ ...noModifiers, NativeCode: code, QTKeyCode: qtCode, VKeyCode: code },
			{ ...noModifiers, NativeCode: -1, QTKeyCode: 33554431, VKeyCode: -1 },
		],
	};
}

/** Page 0: Claudio's face, spread across all fifteen keys. */
function facePage() {
	const actions = {};
	for (let row = 0; row < 3; row++) {
		for (let column = 0; column < 5; column++) {
			actions[`${column},${row}`] = tile(FACE_UUID, {}, "Claudio's face");
		}
	}
	return actions;
}

/**
 * Page 1: eight of Claudio's ten actions (expert prompt and explain simply move to the
 * palette key, replaced here by a bare Return and a bare Escape), two dictate keys, and
 * the three keys that move between pages.
 */
function actionsPage() {
	const action = (id, name) => tile(ACTION_UUID, { id }, name);
	return {
		"0,0": action("correct", "Correct"),
		"1,0": action("translateFR", "Translate (FR)"),
		"2,0": action("translateEN", "Translate (EN)"),
		"3,0": action("professionalTone", "Professional tone"),
		"4,0": action("summarize", "Summarize"),
		"0,1": action("makePrompt", "Prompt"),
		"1,1": action("free", "Free action"),
		"2,1": tile(HOTKEY_UUID, bareKey(36, 16777220), "Return"),
		"3,1": tile(HOTKEY_UUID, bareKey(53, 16777216), "Escape"),
		"4,1": action("palette", "Palette"),
		"0,2": tile(DICTATE_UUID, { language: "primary", output: "cleanup" }, "Dictate"),
		"1,2": tile(DICTATE_UUID, { language: "primary", output: "translateEN" }, "Dictate → EN"),
		"2,2": tile(NAVIGATE_UUID, { target: "face" }, "Claudio"),
		"3,2": tile(NAVIGATE_UUID, { target: "windows" }, "Windows"),
		"4,2": tile(NAVIGATE_UUID, { target: "leave" }, "Leave"),
	};
}

/** Page 2: the eleven window layouts, and two keys back to the face and the actions. */
function windowsPage() {
	const layout = (value) => tile(WINDOW_UUID, { layout: value }, value);
	return {
		"0,0": layout("topLeft"),
		"1,0": layout("topHalf"),
		"2,0": layout("topRight"),
		"3,0": layout("maximize"),
		"4,0": tile(NAVIGATE_UUID, { target: "face" }, "Claudio"),
		"0,1": layout("leftHalf"),
		"1,1": layout("center"),
		"2,1": layout("rightHalf"),
		"3,1": layout("nextScreen"),
		"0,2": layout("bottomLeft"),
		"1,2": layout("bottomHalf"),
		"2,2": layout("bottomRight"),
		"4,2": tile(NAVIGATE_UUID, { target: "actions" }, "Back"),
	};
}

/**
 * One page's own manifest.
 * @param actions Its keys, keyed by "column,row".
 * @returns The manifest Stream Deck expects at `Profiles/<uuid>/manifest.json`.
 */
function pageManifest(actions) {
	// The same shape the app stores its own multi-page profiles in (ProfilesV3): a page
	// carries a name and an icon even when both are blank.
	return { Name: "", Icon: "", Controllers: [{ Type: "Keypad", Actions: actions }] };
}

/**
 * Writes the profile to `destination` (the plugin's own copy by default).
 * @param destination Where to write the `.streamDeckProfile` file.
 */
export async function writeProfile(destination = DEFAULT_DESTINATION) {
	// Lower-case, as the app writes its own: it re-keys every page on import and looks the
	// current page up by that spelling.
	const profileId = randomUUID();
	const faceId = randomUUID();
	const actionsId = randomUUID();
	const windowsId = randomUUID();
	const blankId = randomUUID();

	const zip = new JSZip();
	const base = `${profileId}.sdProfile`;

	zip.file(
		`${base}/manifest.json`,
		JSON.stringify(
			{
				Name: PROFILE_NAME,
				// "1.0" is the single-page format with the keys at the top; pages only exist
				// from "3.0", and the importer picks its parser from this number.
				Version: "3.0",
				// The model of the deck the pages are laid out for; the app asks which
				// device to install on and fills the rest in.
				Device: { Model: DEVICE_MODEL, UUID: "" },
				Pages: { Current: faceId, Default: blankId, Pages: [faceId, actionsId, windowsId] },
			},
			null,
			"\t",
		),
	);
	zip.file(`${base}/Profiles/${faceId}/manifest.json`, JSON.stringify(pageManifest(facePage()), null, "\t"));
	zip.file(`${base}/Profiles/${actionsId}/manifest.json`, JSON.stringify(pageManifest(actionsPage()), null, "\t"));
	zip.file(`${base}/Profiles/${windowsId}/manifest.json`, JSON.stringify(pageManifest(windowsPage()), null, "\t"));
	zip.file(`${base}/Profiles/${blankId}/manifest.json`, JSON.stringify(pageManifest({}), null, "\t"));

	await mkdir(path.dirname(destination), { recursive: true });
	await writeFile(destination, await zip.generateAsync({ type: "nodebuffer" }));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
	await writeProfile();
	console.log(`Wrote ${path.relative(ROOT, DEFAULT_DESTINATION)}`);
}
