import { beforeEach, describe, expect, it, vi } from "vitest";

// The real SDK opens a log file and installs process handlers the moment it is imported;
// the key only needs the base class and the decorator's job, which this stands in for.
vi.mock("@elgato/streamdeck", () => ({
	SingletonAction: class {
		public actions: unknown[] = [];
	},
}));

const { CLAUDIO_LABEL_KEY } = await import("../src/actions/claudio.js");
const { DEFAULT_NAVIGATE_TARGET, NAVIGATE_UUID, NavigateKey } = await import("../src/actions/navigate.js");
const { PAINT_FLOOR_MS } = await import("../src/actions/keys.js");
const { back, windowsPage } = await import("../src/render/glyphs.js");
const { keySvg } = await import("../src/render/key.js");
const { livingKeySvg } = await import("../src/render/living.js");
const { livingGaze } = await import("../src/render/look.js");
const { IdleReturn, PAGES, PROFILE_NAME } = await import("../src/idle.js");
const { Store } = await import("../src/state/store.js");
const { appear, decodeImage, DECK, fakeKey, press } = await import("./fakes.js");

type BridgeState = import("../src/bridge/protocol.js").BridgeState;
type FakeKey = import("./fakes.js").FakeKey;

const IDLE: BridgeState = { gaze: "repos", activity: "idle", phase: null, label: null, locked: false };

/** Stream Deck showing a profile, as far as the return can tell. */
function fakeSwitch() {
	return vi.fn(async (_deviceId: string, _profile?: string, _page?: number) => {});
}

/** Lets the painter's floor pass, so a drawing it is holding back goes out. */
async function painted(): Promise<void> {
	await new Promise((resolve) => setTimeout(resolve, PAINT_FLOOR_MS + 20));
}

/** The image the key was last given. */
function lastImage(key: FakeKey): string {
	const call = key.setImage.mock.calls.at(-1);
	expect(call, "the key was never drawn").toBeDefined();

	return decodeImage(call![0]);
}

describe("NavigateKey", () => {
	let switchProfile: ReturnType<typeof fakeSwitch>;
	let idle: InstanceType<typeof IdleReturn>;
	let store: InstanceType<typeof Store>;
	let deps: {
		store: InstanceType<typeof Store>;
		translate: (key: string) => string;
		touch: ReturnType<typeof vi.fn<(deviceId: string) => void>>;
		show: (deviceId: string, page: "face" | "actions" | "windows") => Promise<void>;
		leave: (deviceId: string) => Promise<void>;
	};
	let action: InstanceType<typeof NavigateKey>;

	beforeEach(() => {
		switchProfile = fakeSwitch();
		idle = new IdleReturn(switchProfile);
		store = new Store();
		deps = {
			store,
			translate: (key: string) => `[${key}]`,
			touch: vi.fn<(deviceId: string) => void>(),
			show: (deviceId, page) => idle.show(deviceId, page),
			leave: (deviceId) => idle.leave(deviceId),
		};
		action = new NavigateKey(deps);
	});

	it("answers to the action identifier from the manifest", () => {
		expect(action.manifestId).toBe("com.okonoma.claudio.navigate");
		expect(NAVIGATE_UUID).toBe("com.okonoma.claudio.navigate");
	});

	it("goes to the actions page, until told otherwise", () => {
		expect(DEFAULT_NAVIGATE_TARGET).toBe("actions");
	});

	it("takes the deck to the actions page, by its number", async () => {
		const key = fakeKey();
		await appear(action, key, { target: "actions" });

		await press(action, key, { target: "actions" });

		expect(switchProfile).toHaveBeenCalledWith(DECK, PROFILE_NAME, PAGES.actions);
		expect(deps.touch).toHaveBeenCalledWith(DECK);
	});

	it("takes the deck to the windows page, by its number", async () => {
		const key = fakeKey();

		await press(action, key, { target: "windows" });

		expect(switchProfile).toHaveBeenCalledWith(DECK, PROFILE_NAME, PAGES.windows);
	});

	it("takes the deck home to the face, by its number", async () => {
		const key = fakeKey();

		await press(action, key, { target: "face" });

		expect(switchProfile).toHaveBeenCalledWith(DECK, PROFILE_NAME, PAGES.face);
	});

	it("gives the deck back to whatever it was showing before, naming no profile", async () => {
		const key = fakeKey();

		await press(action, key, { target: "leave" });

		expect(switchProfile).toHaveBeenCalledWith(DECK);
		expect(switchProfile.mock.calls[0]).toHaveLength(1);
	});

	it("falls back to the actions page when a key carries no target", async () => {
		const key = fakeKey();

		await press(action, key, {});

		expect(switchProfile).toHaveBeenCalledWith(DECK, PROFILE_NAME, PAGES.actions);
	});

	it("draws the way back, under a label of its own", async () => {
		const key = fakeKey();

		await appear(action, key, { target: "actions" });
		await painted();

		expect(lastImage(key)).toBe(keySvg({ glyph: back(), label: "[navigate.actions.label]" }));
	});

	it("draws leaving with the same glyph as going back, but its own words", async () => {
		const key = fakeKey();

		await appear(action, key, { target: "leave" });
		await painted();

		expect(lastImage(key)).toBe(keySvg({ glyph: back(), label: "[navigate.leave.label]" }));
	});

	it("draws the door to the windows page", async () => {
		const key = fakeKey();

		await appear(action, key, { target: "windows" });
		await painted();

		expect(lastImage(key)).toBe(keySvg({ glyph: windowsPage(), label: "[navigate.windows.label]" }));
	});

	it("draws the mascot himself for the way home, under his own name", async () => {
		store.update({ connected: true, state: IDLE });
		const key = fakeKey();

		await appear(action, key, { target: "face" });
		await painted();

		expect(lastImage(key)).toBe(
			livingKeySvg({ gaze: livingGaze({ state: IDLE, connected: true, eyesClosed: false }), label: `[${CLAUDIO_LABEL_KEY}]` }),
		);
	});

	it("dims the mascot while nobody answers, but still leads home", async () => {
		const key = fakeKey();

		await appear(action, key, { target: "face" });
		await painted();

		expect(lastImage(key)).toContain('opacity="0.45"');
	});

	it("follows the app for the face target alone", async () => {
		const face = fakeKey("key-face");
		const backKey = fakeKey("key-back");
		(action as unknown as { actions: unknown[] }).actions = [face, backKey];
		await appear(action, face, { target: "face" });
		await appear(action, backKey, { target: "actions" });
		await painted();
		face.setImage.mockClear();
		backKey.setImage.mockClear();

		store.update({ connected: true, state: { ...IDLE, gaze: "fait" } });
		await painted();

		expect(face.setImage).toHaveBeenCalled();
		expect(backKey.setImage).not.toHaveBeenCalled();
	});
});
