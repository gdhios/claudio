import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import { CLAUDIO_ACTION_IDS, DICTATION_LANGUAGES, DICTATION_OUTPUTS, WINDOW_LAYOUTS } from "../src/bridge/protocol.js";
import { IDLE_SECONDS_CHOICES } from "../src/idle.js";
import { DICTATE_PHRASES } from "../src/render/dictate.js";

/** The three plain doors a navigate key can be set to; "face" wears the mascot's own name. */
const NAVIGATE_TARGETS = ["actions", "windows", "leave"];

/**
 * The same words live in two places, because two different readers need them: the plugin
 * process translates from `fr.json` / `en.json`, and the property inspectors run in a
 * browser where sdpi-components resolves `__MSG_…__` against `ui/locale.js` alone. This
 * is what keeps the two from drifting apart.
 */

const pluginDir = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "com.okonoma.claudio.sdPlugin");

type Labels = Record<string, { label?: string } | undefined>;

/** The `dictate` block holds the labels of the outputs and the words for each phase. */
type DictateLocale = Record<string, { label?: string } | string | undefined>;

type Locale = {
	action?: Labels;
	window?: Labels;
	dictate?: DictateLocale;
	language?: Labels;
	inspector?: Record<string, string>;
	claudio?: { label?: string };
	navigate?: Labels;
	face?: { disconnected?: { message?: string } };
	idleSeconds?: Labels;
};

/**
 * Reads the label of an output, wherever the block comes from.
 * @param locale Block to read.
 * @param output The output.
 * @returns The label, if there is one.
 */
function outputLabel(locale: Locale, output: string): string | undefined {
	const entry = locale.dictate?.[output];

	return typeof entry === "object" ? entry.label : undefined;
}

/**
 * Reads the `Localization` block of one of the files the plugin process translates from.
 * @param language Language to read.
 * @returns Its localizations.
 */
function pluginLocale(language: string): Locale {
	const file = JSON.parse(readFileSync(path.join(pluginDir, `${language}.json`), "utf8")) as {
		Localization?: Locale;
	};
	expect(file.Localization, `${language}.json has no Localization block`).toBeDefined();

	return file.Localization!;
}

/**
 * Reads one action's own manifest metadata — its name and tooltip — from one of the files
 * the plugin process translates from. This sits beside the `Localization` block, not in it.
 * @param language Language to read.
 * @param uuid Identifier of the action.
 * @returns The metadata, or an empty object when the file carries none.
 */
function pluginActionMeta(language: string, uuid: string): { Name?: string; Tooltip?: string } {
	const file = JSON.parse(readFileSync(path.join(pluginDir, `${language}.json`), "utf8")) as Record<
		string,
		{ Name?: string; Tooltip?: string } | undefined
	>;

	return file[uuid] ?? {};
}

/**
 * Runs `ui/locale.js` the way a property inspector would, against a stub of the library
 * it assigns to, and returns what it assigned.
 * @returns The inspector's locales, by language.
 */
function inspectorLocales(): Record<string, Locale> {
	const source = readFileSync(path.join(pluginDir, "ui", "locale.js"), "utf8");
	const stub: { i18n: { locales?: Record<string, Locale> } } = { i18n: {} };
	new Function("SDPIComponents", source)(stub);
	expect(stub.i18n.locales, "ui/locale.js assigned no locales").toBeDefined();

	return stub.i18n.locales!;
}

const LANGUAGES = ["fr", "en"];
const inspector = inspectorLocales();

describe("the translation files and the property inspectors agree", () => {
	for (const language of LANGUAGES) {
		describe(language, () => {
			const plugin = pluginLocale(language);

			it("is a language the inspectors know", () => {
				expect(inspector[language]).toBeDefined();
			});

			it.each(CLAUDIO_ACTION_IDS)("labels the %s action in both places, with the same word", (id) => {
				const inPlugin = plugin.action?.[id]?.label;
				const inInspector = inspector[language]?.action?.[id]?.label;

				expect(inPlugin, `${language}.json is missing action.${id}.label`).toBeTruthy();
				expect(inInspector, `ui/locale.js is missing ${language}.action.${id}.label`).toBeTruthy();
				expect(inInspector).toBe(inPlugin);
			});

			it.each(WINDOW_LAYOUTS)("labels the %s layout in both places, with the same word", (layout) => {
				const inPlugin = plugin.window?.[layout]?.label;
				const inInspector = inspector[language]?.window?.[layout]?.label;

				expect(inPlugin, `${language}.json is missing window.${layout}.label`).toBeTruthy();
				expect(inInspector, `ui/locale.js is missing ${language}.window.${layout}.label`).toBeTruthy();
				expect(inInspector).toBe(inPlugin);
			});

			it.each(DICTATION_OUTPUTS)("labels the %s dictation in both places, with the same word", (output) => {
				const inPlugin = outputLabel(plugin, output);
				const inInspector = outputLabel(inspector[language] ?? {}, output);

				expect(inPlugin, `${language}.json is missing dictate.${output}.label`).toBeTruthy();
				expect(inInspector, `ui/locale.js is missing ${language}.dictate.${output}.label`).toBeTruthy();
				expect(inInspector).toBe(inPlugin);
			});

			it.each(DICTATE_PHRASES)("says what the key shows while it is %s", (phrase) => {
				// Only the plugin process ever says these: the inspector shows no dictation.
				expect(plugin.dictate?.[phrase], `${language}.json is missing dictate.${phrase}`).toBeTruthy();
				expect(typeof plugin.dictate?.[phrase]).toBe("string");
			});

			it.each(DICTATION_LANGUAGES)("offers the %s language in the inspector", (choice) => {
				expect(inspector[language]?.language?.[choice]?.label).toBeTruthy();
			});

			it("names every inspector field, and explains the second language", () => {
				expect(inspector[language]?.inspector?.action).toBeTruthy();
				expect(inspector[language]?.inspector?.layout).toBeTruthy();
				expect(inspector[language]?.inspector?.language).toBeTruthy();
				expect(inspector[language]?.inspector?.output).toBeTruthy();
				expect(inspector[language]?.inspector?.secondary).toBeTruthy();
				expect(inspector[language]?.inspector?.idleSeconds).toBeTruthy();
			});

			it.each(IDLE_SECONDS_CHOICES)("offers %s seconds as an idle delay, in the inspector", (seconds) => {
				expect(
					inspector[language]?.idleSeconds?.[String(seconds)]?.label,
					`ui/locale.js is missing ${language}.idleSeconds.${seconds}.label`,
				).toBeTruthy();
			});

			it("names the mascot key, the same word under his own key and on the way home", () => {
				expect(pluginActionMeta(language, "com.okonoma.claudio.claudio").Name).toBeTruthy();
				expect(plugin.claudio?.label, `${language}.json is missing claudio.label`).toBeTruthy();
			});

			it("names the face and the navigation actions", () => {
				expect(pluginActionMeta(language, "com.okonoma.claudio.face").Name).toBeTruthy();
				expect(pluginActionMeta(language, "com.okonoma.claudio.navigate").Name).toBeTruthy();
			});

			it("says how to reach the app once it is gone", () => {
				expect(
					plugin.face?.disconnected?.message,
					`${language}.json is missing face.disconnected.message`,
				).toBeTruthy();
			});

			it.each(NAVIGATE_TARGETS)("labels the %s navigation target", (target) => {
				expect(plugin.navigate?.[target]?.label, `${language}.json is missing navigate.${target}.label`).toBeTruthy();
			});
		});
	}

	it("carries nothing beyond the members the protocol defines", () => {
		for (const language of LANGUAGES) {
			expect(Object.keys(pluginLocale(language).action ?? {}).sort()).toEqual([...CLAUDIO_ACTION_IDS].sort());
			expect(Object.keys(pluginLocale(language).window ?? {}).sort()).toEqual([...WINDOW_LAYOUTS].sort());
			expect(Object.keys(pluginLocale(language).dictate ?? {}).sort()).toEqual(
				[...DICTATION_OUTPUTS, ...DICTATE_PHRASES].sort(),
			);
		}
	});

	it("says something different in each language", () => {
		expect(pluginLocale("fr").action?.correct?.label).not.toBe(pluginLocale("en").action?.correct?.label);
		expect(pluginLocale("fr").face?.disconnected?.message).not.toBe(pluginLocale("en").face?.disconnected?.message);
		expect(pluginLocale("fr").navigate?.leave?.label).not.toBe(pluginLocale("en").navigate?.leave?.label);
	});
});

describe("the property inspectors stand on their own", () => {
	const pages = ["action.html", "window.html", "dictate.html", "face.html"];

	it("lets the Action key choose every action the protocol defines", () => {
		const html = readFileSync(path.join(pluginDir, "ui", "action.html"), "utf8");

		for (const id of CLAUDIO_ACTION_IDS) {
			expect(html, `action.html offers no ${id}`).toContain(`<option value="${id}">__MSG_action.${id}.label__</option>`);
		}
	});

	it("lets the Dictate key choose its language and its output", () => {
		const html = readFileSync(path.join(pluginDir, "ui", "dictate.html"), "utf8");

		expect(html).toContain('setting="language"');
		expect(html).toContain('setting="output"');
		for (const value of [...DICTATION_LANGUAGES, ...DICTATION_OUTPUTS]) {
			expect(html, `dictate.html offers no ${value}`).toContain(`value="${value}"`);
		}
	});

	it("lets a face tile choose how long its deck waits before coming home", () => {
		const html = readFileSync(path.join(pluginDir, "ui", "face.html"), "utf8");

		expect(html).toContain('setting="idleSeconds"');
		for (const seconds of IDLE_SECONDS_CHOICES) {
			expect(html, `face.html offers no ${seconds}`).toContain(`value="${seconds}"`);
		}
	});

	it.each(pages)("%s loads sdpi-components from beside it, not from the network", (page) => {
		const html = readFileSync(path.join(pluginDir, "ui", page), "utf8");

		expect(html).toContain('src="./vendor/sdpi-components.js"');
		// A property inspector with no network would otherwise render none of its controls.
		expect(html).not.toMatch(/src="https?:/);
	});

	it("ships the library it points at, licence banner and all", () => {
		const library = readFileSync(path.join(pluginDir, "ui", "vendor", "sdpi-components.js"), "utf8");

		expect(library).toContain("@license");
		expect(library).toContain("sdpi-components");
		expect(library.length).toBeGreaterThan(10_000);
	});
});
