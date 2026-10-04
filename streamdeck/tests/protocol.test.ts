import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import {
	type BridgeInbound,
	parseOutbound,
	PROTOCOL_VERSION,
	ProtocolError,
	serializeInbound,
} from "../src/bridge/protocol.js";

const fixturesDir = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "protocol", "fixtures");

/**
 * Reads a fixture as raw text, exactly as it travels over the wire.
 */
function fixtureText(name: string): string {
	return readFileSync(path.join(fixturesDir, `${name}.json`), "utf8").trim();
}

/**
 * Reads a fixture as the JSON value it represents.
 */
function fixtureJson(name: string): unknown {
	return JSON.parse(fixtureText(name));
}

/** Frames the plugin sends to the app. */
const inboundFixtures: Record<string, BridgeInbound> = {
	hello: {
		type: "hello",
		v: PROTOCOL_VERSION,
		token: "3f9a1c0e7b2d4f6a8c1e3b5d7f9a2c4e6b8d0f1a3c5e7b9d2f4a6c8e0b1d3f5a",
		plugin: "1.13.0",
	},
	"action-correct": { type: "action", id: "correct" },
	"action-free": { type: "action", id: "free" },
	"action-palette": { type: "action", id: "palette" },
	"action-whats-playing": { type: "action", id: "whatsPlaying" },
	"dictation-down": { type: "dictation", event: "down", language: "primary", output: "cleanup" },
	"dictation-down-secondary": { type: "dictation", event: "down", language: "secondary", output: "cleanup" },
	"dictation-down-translate": { type: "dictation", event: "down", language: "primary", output: "translateEN" },
	"dictation-up": { type: "dictation", event: "up" },
	"dictation-cancel": { type: "dictation", event: "cancel" },
	"window-top-left": { type: "window", layout: "topLeft" },
	"window-next-screen": { type: "window", layout: "nextScreen" },
	"open-settings": { type: "open", target: "settings" },
};

/** Frames the app sends to the plugin. */
const outboundFixtures = [
	"welcome",
	"state-idle",
	"state-correction-streaming",
	"state-correction-no-selection",
	"state-dictation-listening",
	"state-dictation-cleaning-locked",
	"state-dictation-done",
	"state-dictation-empty",
	"state-dictation-error",
	"level",
	"bye",
	"error-version",
];

describe("fixtures", () => {
	it("covers every fixture file, so a new frame shape cannot slip in untested", () => {
		const onDisk = readdirSync(fixturesDir)
			.filter((name) => name.endsWith(".json"))
			.map((name) => name.replace(/\.json$/, ""))
			.sort();
		const covered = [...Object.keys(inboundFixtures), ...outboundFixtures].sort();

		expect(covered).toEqual(onDisk);
	});
});

describe("serializeInbound", () => {
	for (const [name, message] of Object.entries(inboundFixtures)) {
		it(`serializes ${name} to the fixture frame`, () => {
			expect(JSON.parse(serializeInbound(message))).toEqual(fixtureJson(name));
		});
	}

	it("omits the language and output of a dictation that is not a key down", () => {
		expect(serializeInbound({ type: "dictation", event: "up" })).toBe('{"type":"dictation","event":"up"}');
	});
});

describe("parseOutbound", () => {
	for (const name of outboundFixtures) {
		it(`parses ${name} into the value the fixture describes`, () => {
			expect(parseOutbound(fixtureText(name))).toEqual(fixtureJson(name));
		});
	}

	it("reads the state carried by a welcome", () => {
		const welcome = parseOutbound(fixtureText("welcome"));

		expect(welcome).toMatchObject({
			type: "welcome",
			v: 1,
			app: "1.13.0",
			state: { gaze: "repos", activity: "idle", phase: null, label: null, locked: false },
		});
	});

	it("reads a state whose phase and label are set", () => {
		expect(parseOutbound(fixtureText("state-dictation-cleaning-locked"))).toMatchObject({
			phase: "cleaning",
			label: "Nettoyage…",
			locked: true,
		});
	});

	it.each([
		["a frame that is not JSON", "not json"],
		["a frame that is not an object", '"state"'],
		["an unknown type", '{"type":"nope"}'],
		["a frame the plugin sends", '{"type":"action","id":"correct"}'],
		["a gaze outside the enum", '{"type":"state","gaze":"asleep","activity":"idle","phase":null,"label":null,"locked":false}'],
		["an activity outside the enum", '{"type":"state","gaze":"repos","activity":"cooking","phase":null,"label":null,"locked":false}'],
		["a state missing its locked flag", '{"type":"state","gaze":"repos","activity":"idle","phase":null,"label":null}'],
		["a level above one", '{"type":"level","value":1.5}'],
		["a level that is not a number", '{"type":"level","value":"loud"}'],
		["an error code outside the enum", '{"type":"error","code":"teapot","message":"nope"}'],
		["a welcome without a state", '{"type":"welcome","v":1,"app":"1.13.0"}'],
	])("rejects %s", (_why, text) => {
		expect(() => parseOutbound(text)).toThrow();
	});

	it("throws a ProtocolError naming the offending field", () => {
		expect(() => parseOutbound('{"type":"level","value":"loud"}')).toThrow(ProtocolError);
		expect(() => parseOutbound('{"type":"level","value":"loud"}')).toThrow(/value/);
	});
});
