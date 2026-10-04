import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// The real SDK opens a log file and installs process handlers the moment it is imported;
// the key only needs the base class and the decorator's job, which this stands in for.
vi.mock("@elgato/streamdeck", () => ({
	SingletonAction: class {
		public actions: unknown[] = [];
	},
}));

const { Blink, BLINK_CLOSED_MS, BLINK_MAX_MS, BLINK_MIN_MS } = await import("../src/actions/blink.js");
const { CLAUDIO_UUID, ClaudioKey, INSTALL_PROFILE_EVENT } = await import("../src/actions/claudio.js");
const { PAINT_FLOOR_MS } = await import("../src/actions/keys.js");
const { livingGaze } = await import("../src/render/look.js");
const { livingKeySvg } = await import("../src/render/living.js");
const { appear, DECK, decodeImage, disappear, fakeKey, fakeKeyDeps, press } = await import("./fakes.js");

type BridgeState = import("../src/bridge/protocol.js").BridgeState;
type FakeKey = import("./fakes.js").FakeKey;

/** Claudio with nothing to do. */
const IDLE: BridgeState = { gaze: "repos", activity: "idle", phase: null, label: null, locked: false };

describe("Blink", () => {
	let redraw: ReturnType<typeof vi.fn<() => void>>;

	beforeEach(() => {
		vi.useFakeTimers();
		redraw = vi.fn<() => void>();
	});

	afterEach(() => {
		vi.useRealTimers();
	});

	it("keeps his eyes open until he is told he may close them", async () => {
		const blink = new Blink(redraw, () => 0);

		await vi.advanceTimersByTimeAsync(BLINK_MAX_MS * 3);

		expect(blink.closed).toBe(false);
		expect(redraw).not.toHaveBeenCalled();
	});

	it("closes his eyes for a moment, then opens them again", async () => {
		const blink = new Blink(redraw, () => 0);
		blink.follow(true);

		await vi.advanceTimersByTimeAsync(BLINK_MIN_MS);

		expect(blink.closed).toBe(true);
		expect(redraw).toHaveBeenCalledOnce();

		await vi.advanceTimersByTimeAsync(BLINK_CLOSED_MS);

		expect(blink.closed).toBe(false);
		expect(redraw).toHaveBeenCalledTimes(2);
	});

	it("blinks again, and again, at a pace that is never quite the same", async () => {
		const blink = new Blink(redraw, () => 1);
		blink.follow(true);

		await vi.advanceTimersByTimeAsync(BLINK_MIN_MS + 50);

		// The longest pace this time: the shortest one would have blinked by now.
		expect(blink.closed).toBe(false);

		await vi.advanceTimersByTimeAsync(BLINK_MAX_MS - BLINK_MIN_MS);

		expect(blink.closed).toBe(true);

		await vi.advanceTimersByTimeAsync(BLINK_CLOSED_MS);

		expect(blink.closed).toBe(false);

		await vi.advanceTimersByTimeAsync(BLINK_MAX_MS);

		expect(blink.closed).toBe(true);
		expect(redraw).toHaveBeenCalledTimes(3);
	});

	it("opens his eyes at once when he is no longer allowed to blink", async () => {
		const blink = new Blink(redraw, () => 0);
		blink.follow(true);
		await vi.advanceTimersByTimeAsync(BLINK_MIN_MS);
		redraw.mockClear();

		blink.follow(false);

		expect(blink.closed).toBe(false);
		expect(redraw).toHaveBeenCalledOnce();
	});

	it("says nothing when it stops with his eyes already open", async () => {
		const blink = new Blink(redraw, () => 0);
		blink.follow(true);

		blink.follow(false);

		expect(redraw).not.toHaveBeenCalled();
	});

	it("keeps one rhythm however often it is told to carry on", async () => {
		const blink = new Blink(redraw, () => 0);

		blink.follow(true);
		blink.follow(true);
		blink.follow(true);
		await vi.advanceTimersByTimeAsync(BLINK_MIN_MS);

		expect(redraw).toHaveBeenCalledOnce();
	});

	it("stops for good when the plugin goes", async () => {
		const blink = new Blink(redraw, () => 0);
		blink.follow(true);

		blink.stop();
		await vi.advanceTimersByTimeAsync(BLINK_MAX_MS * 3);

		expect(redraw).not.toHaveBeenCalled();
	});
});

describe("livingGaze", () => {
	it("looks at you while the app has nothing to say", () => {
		expect(livingGaze({ state: null, connected: true, eyesClosed: false })).toBe("repos");
	});

	it("wears the look the app reports", () => {
		expect(livingGaze({ state: { ...IDLE, gaze: "fait" }, connected: true, eyesClosed: false })).toBe("fait");
	});

	it("empties when nobody answers, whatever the eyes were doing", () => {
		expect(livingGaze({ state: IDLE, connected: false, eyesClosed: true })).toBe("vide");
	});

	it("closes his eyes only when he had nothing else to do with them", () => {
		expect(livingGaze({ state: IDLE, connected: true, eyesClosed: true })).toBe("veille");
		// Mid-answer his eyes are already closed, and a blink must not undo what he shows.
		expect(livingGaze({ state: { ...IDLE, gaze: "fait" }, connected: true, eyesClosed: true })).toBe("fait");
	});
});

describe("ClaudioKey", () => {
	let deps: ReturnType<typeof fakeKeyDeps>;
	let action: InstanceType<typeof ClaudioKey>;
	let key: FakeKey;

	beforeEach(() => {
		vi.useFakeTimers();
		deps = fakeKeyDeps();
		action = new ClaudioKey({ ...deps, installProfile: vi.fn(async () => {}) });
		key = fakeKey();
		(action as unknown as { actions: unknown[] }).actions = [key];
	});

	afterEach(() => {
		action.stop();
		vi.useRealTimers();
	});

	/** Lets every redraw run to the end, floor included. */
	async function painted(): Promise<void> {
		await vi.advanceTimersByTimeAsync(PAINT_FLOOR_MS + 20);
	}

	/** The image the key was last given. */
	function lastImage(): string {
		const call = key.setImage.mock.calls.at(-1);
		expect(call, "the key was never drawn").toBeDefined();

		return decodeImage(call![0]);
	}

	it("answers to the action identifier from the manifest", () => {
		expect(action.manifestId).toBe("com.okonoma.claudio.claudio");
		expect(CLAUDIO_UUID).toBe("com.okonoma.claudio.claudio");
	});

	it("draws the mascot under his own name", async () => {
		deps.store.update({ connected: true, state: IDLE });

		await appear(action, key);
		await painted();

		expect(lastImage()).toBe(livingKeySvg({ gaze: "repos", label: "[claudio.label]" }));
	});

	it("wears what the app is doing", async () => {
		await appear(action, key);
		deps.store.update({ connected: true, state: { ...IDLE, gaze: "veille" } });
		await painted();

		expect(lastImage()).toBe(livingKeySvg({ gaze: "veille", label: "[claudio.label]" }));
	});

	it("goes dim and empty-eyed when nobody answers", async () => {
		await appear(action, key);
		await painted();

		expect(lastImage()).toBe(livingKeySvg({ gaze: "vide", label: "[claudio.label]", dimmed: true }));
	});

	it("blinks while he is waiting, and only then", async () => {
		deps.store.update({ connected: true, state: IDLE });
		await appear(action, key);

		// The eyes close after the shortest pace, since the suite pins the pace down.
		await vi.advanceTimersByTimeAsync(BLINK_MIN_MS + 50);

		expect(lastImage()).toBe(livingKeySvg({ gaze: "veille", label: "[claudio.label]" }));

		await vi.advanceTimersByTimeAsync(BLINK_CLOSED_MS);

		expect(lastImage()).toBe(livingKeySvg({ gaze: "repos", label: "[claudio.label]" }));
	});

	it("does not blink at a deck nobody answers", async () => {
		await appear(action, key);
		await vi.advanceTimersByTimeAsync(BLINK_MAX_MS * 2 + BLINK_CLOSED_MS);

		expect(lastImage()).toBe(livingKeySvg({ gaze: "vide", label: "[claudio.label]", dimmed: true }));
	});

	it("opens Claudio's palette when it is pressed", async () => {
		deps.store.update({ connected: true, state: IDLE });

		await press(action, key);

		expect(deps.bridge.send).toHaveBeenCalledWith({ type: "action", id: "palette" });
		expect(deps.touch).toHaveBeenCalledWith(DECK);
	});

	it("takes the user to Claudio when nobody answers the press", async () => {
		await press(action, key);

		expect(deps.bridge.send).not.toHaveBeenCalled();
		expect(key.showAlert).toHaveBeenCalledOnce();
		expect(deps.openClaudio).toHaveBeenCalledOnce();
	});

	it("warns when the connection goes between the look and the press", async () => {
		deps.store.update({ connected: true, state: IDLE });
		deps.bridge.send.mockReturnValue(false);

		await press(action, key);

		expect(key.showAlert).toHaveBeenCalledOnce();
	});

	it("stops drawing a key that left the page", async () => {
		deps.store.update({ connected: true, state: IDLE });
		await appear(action, key);
		await painted();
		key.setImage.mockClear();

		await disappear(action, key);
		(action as unknown as { actions: unknown[] }).actions = [];
		deps.store.setState({ ...IDLE, gaze: "fait" });
		await painted();

		expect(key.setImage).not.toHaveBeenCalled();
	});
});

describe("ClaudioKey's inspector", () => {
	it("installs the profile on the key's own deck when the button asks", async () => {
		const installProfile = vi.fn(async () => {});
		const key = new ClaudioKey({ ...fakeKeyDeps(), installProfile });
		const action = fakeKey("key-1", "deck-blue");

		await key.onSendToPlugin({ action, payload: { event: INSTALL_PROFILE_EVENT } } as never);

		expect(installProfile).toHaveBeenCalledWith("deck-blue");
	});

	it("ignores anything else the inspector might send", async () => {
		const installProfile = vi.fn(async () => {});
		const key = new ClaudioKey({ ...fakeKeyDeps(), installProfile });

		await key.onSendToPlugin({ action: fakeKey(), payload: { event: "somethingElse" } } as never);
		await key.onSendToPlugin({ action: fakeKey(), payload: "installProfile" } as never);

		expect(installProfile).not.toHaveBeenCalled();
	});
});
