/**
 * The wire contract between Claudio and this plugin, version 1.
 *
 * The frames in `protocol/fixtures/` are the contract; the app's Swift tests and this
 * module's tests load the very same files. Enum members below are storage keys and API
 * identifiers on the app side: members may be added, never renamed. That is also why a
 * few of them read as French words — they are the app's own stored raw values, not text
 * anybody sees.
 */

/** Version carried by `hello` and `welcome`; everything else is implied by the handshake. */
export const PROTOCOL_VERSION = 1;

/**
 * What the Action key can launch: an action run on the current selection, the palette,
 * or "What's playing?", which reads the player instead.
 */
export const CLAUDIO_ACTION_IDS = [
	"correct",
	"makePrompt",
	"expertPrompt",
	"translateFR",
	"translateEN",
	"professionalTone",
	"summarize",
	"simplify",
	"free",
	"palette",
	"whatsPlaying",
] as const;

export type ClaudioActionId = (typeof CLAUDIO_ACTION_IDS)[number];

/** Places a window can be sent to. */
export const WINDOW_LAYOUTS = [
	"leftHalf",
	"rightHalf",
	"topHalf",
	"bottomHalf",
	"topLeft",
	"topRight",
	"bottomLeft",
	"bottomRight",
	"maximize",
	"center",
	"nextScreen",
] as const;

export type WindowLayout = (typeof WINDOW_LAYOUTS)[number];

/** Steps of a dictation press. */
export const DICTATION_EVENTS = ["down", "up", "cancel"] as const;

export type DictationEvent = (typeof DICTATION_EVENTS)[number];

/** Which of the two configured dictation languages to listen in. */
export const DICTATION_LANGUAGES = ["primary", "secondary"] as const;

export type DictationLanguage = (typeof DICTATION_LANGUAGES)[number];

/** What the app does with a finished dictation. */
export const DICTATION_OUTPUTS = ["cleanup", "translateEN", "makePrompt"] as const;

export type DictationOutput = (typeof DICTATION_OUTPUTS)[number];

/** The mascot's four looks, one per state of the app. */
export const GAZES = ["repos", "veille", "fait", "vide"] as const;

export type Gaze = (typeof GAZES)[number];

/** What the app is busy with; a dictation session wins over a correction session. */
export const ACTIVITIES = ["idle", "correction", "dictation"] as const;

export type Activity = (typeof ACTIVITIES)[number];

/** Reasons the app closes a connection. */
export const ERROR_CODES = ["version", "token"] as const;

export type ErrorCode = (typeof ERROR_CODES)[number];

/**
 * Everything the plugin needs to draw a key.
 *
 * `phase` is the bare Swift case name (`streaming`, `noSelection`, `listening`, …) and
 * `label` the app's own progress text, in the app's language.
 */
export type BridgeState = {
	gaze: Gaze;
	activity: Activity;
	phase: string | null;
	label: string | null;
	locked: boolean;
};

/** A frame the plugin sends to the app. */
export type BridgeInbound =
	| { type: "hello"; v: number; token: string; plugin: string }
	| { type: "action"; id: ClaudioActionId }
	| { type: "dictation"; event: "down"; language: DictationLanguage; output: DictationOutput }
	| { type: "dictation"; event: "up" | "cancel" }
	| { type: "window"; layout: WindowLayout }
	| { type: "open"; target: "settings" };

/** A frame the app sends to the plugin. */
export type BridgeOutbound =
	| { type: "welcome"; v: number; app: string; state: BridgeState }
	| ({ type: "state" } & BridgeState)
	| { type: "level"; value: number }
	| { type: "bye" }
	| { type: "error"; code: ErrorCode; message: string };

/** Raised when a frame does not match the contract. */
export class ProtocolError extends Error {
	public constructor(message: string) {
		super(message);
		this.name = "ProtocolError";
	}
}

/**
 * Renders a frame the plugin sends to the app.
 * @param message Frame to send.
 * @returns The text frame.
 */
export function serializeInbound(message: BridgeInbound): string {
	return JSON.stringify(message);
}

/**
 * Reads a frame the app sent, or throws when it does not match the contract.
 * @param text Text frame received from the app.
 * @returns The frame.
 */
export function parseOutbound(text: string): BridgeOutbound {
	let frame: unknown;
	try {
		frame = JSON.parse(text);
	} catch (cause) {
		throw new ProtocolError(`frame is not JSON: ${(cause as Error).message}`);
	}

	if (!isRecord(frame)) {
		throw new ProtocolError("frame is not an object");
	}

	switch (frame.type) {
		case "welcome":
			return {
				type: "welcome",
				v: readNumber(frame.v, "v"),
				app: readString(frame.app, "app"),
				state: readState(frame.state, "state"),
			};
		case "state":
			return { type: "state", ...readState(frame, "state") };
		case "level":
			return { type: "level", value: readRatio(frame.value, "value") };
		case "bye":
			return { type: "bye" };
		case "error":
			return {
				type: "error",
				code: readMember(frame.code, ERROR_CODES, "code"),
				message: readString(frame.message, "message"),
			};
		default:
			throw new ProtocolError(`unknown frame type: ${JSON.stringify(frame.type)}`);
	}
}

/**
 * Narrows a value to a plain object.
 * @param value Value to narrow.
 * @returns `true` when the value is a plain object.
 */
function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Reads a state, wherever it sits in the frame.
 * @param value Value holding the state's fields.
 * @param field Name of the field, for the error message.
 * @returns The state.
 */
function readState(value: unknown, field: string): BridgeState {
	if (!isRecord(value)) {
		throw new ProtocolError(`${field} is not an object`);
	}

	return {
		gaze: readMember(value.gaze, GAZES, `${field}.gaze`),
		activity: readMember(value.activity, ACTIVITIES, `${field}.activity`),
		phase: readNullableString(value.phase, `${field}.phase`),
		label: readNullableString(value.label, `${field}.label`),
		locked: readBoolean(value.locked, `${field}.locked`),
	};
}

/**
 * Reads a value that must belong to a fixed set.
 * @param value Value to read.
 * @param members Allowed members.
 * @param field Name of the field, for the error message.
 * @returns The member.
 */
function readMember<T extends string>(value: unknown, members: readonly T[], field: string): T {
	if (typeof value !== "string" || !members.includes(value as T)) {
		throw new ProtocolError(`${field} is not one of ${members.join(", ")}: ${JSON.stringify(value)}`);
	}

	return value as T;
}

/**
 * Reads a string.
 * @param value Value to read.
 * @param field Name of the field, for the error message.
 * @returns The string.
 */
function readString(value: unknown, field: string): string {
	if (typeof value !== "string") {
		throw new ProtocolError(`${field} is not a string: ${JSON.stringify(value)}`);
	}

	return value;
}

/**
 * Reads a string that the app is allowed to leave empty.
 * @param value Value to read.
 * @param field Name of the field, for the error message.
 * @returns The string, or `null`.
 */
function readNullableString(value: unknown, field: string): string | null {
	return value === null ? null : readString(value, field);
}

/**
 * Reads a boolean.
 * @param value Value to read.
 * @param field Name of the field, for the error message.
 * @returns The boolean.
 */
function readBoolean(value: unknown, field: string): boolean {
	if (typeof value !== "boolean") {
		throw new ProtocolError(`${field} is not a boolean: ${JSON.stringify(value)}`);
	}

	return value;
}

/**
 * Reads a finite number.
 * @param value Value to read.
 * @param field Name of the field, for the error message.
 * @returns The number.
 */
function readNumber(value: unknown, field: string): number {
	if (typeof value !== "number" || !Number.isFinite(value)) {
		throw new ProtocolError(`${field} is not a number: ${JSON.stringify(value)}`);
	}

	return value;
}

/**
 * Reads a number between zero and one, inclusive.
 * @param value Value to read.
 * @param field Name of the field, for the error message.
 * @returns The number.
 */
function readRatio(value: unknown, field: string): number {
	const ratio = readNumber(value, field);
	if (ratio < 0 || ratio > 1) {
		throw new ProtocolError(`${field} is outside 0…1: ${ratio}`);
	}

	return ratio;
}
