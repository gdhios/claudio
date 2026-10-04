import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// The real SDK opens a log file and installs process handlers the moment it is imported;
// the key only needs the base class and the decorator's job, which this stands in for.
vi.mock("@elgato/streamdeck", () => ({
	SingletonAction: class {
		public actions: unknown[] = [];
	},
}));

const { BLINK_CLOSED_MS, BLINK_MIN_MS } = await import("../src/actions/blink.js");
const { FACE_UUID, FaceKey, LEVEL_COALESCE_MS } = await import("../src/actions/face-tile.js");
const { PAINT_FLOOR_MS } = await import("../src/actions/keys.js");
const { faceSvg, tileSvg } = await import("../src/render/face.js");
const { DEFAULT_IDLE_SECONDS } = await import("../src/idle.js");
const { appear, decodeImage, disappear, fakeKey, fakeKeyDeps, press } = await import("./fakes.js");

type BridgeState = import("../src/bridge/protocol.js").BridgeState;
type FaceParams = import("../src/render/face.js").FaceParams;
type FakeKey = import("./fakes.js").FakeKey;

const IDLE: BridgeState = { gaze: "repos", activity: "idle", phase: null, label: null, locked: false };
const BLUE = "deck-blue";

/** Claudio at rest, connected, saying nothing — the default a fresh board should show. */
const RESTING: FaceParams = { gaze: "repos", level: 0, glow: false, disconnected: false };

/** The collaborators the face key is built with, plus a way to play level frames. */
function fakeDeps() {
	const listeners = new Set<(value: number) => void>();
	const base = fakeKeyDeps();

	return {
		...base,
		onLevel: (listener: (value: number) => void) => {
			listeners.add(listener);
			return () => listeners.delete(listener);
		},
		hear: (value: number) => {
			for (const listener of [...listeners]) {
				listener(value);
			}
		},
		showActions: vi.fn(async (_deviceId: string) => {}),
		sawFace: vi.fn(),
		setIdleSeconds: vi.fn(),
	};
}

/** Lets every redraw a store or blink change started run to the end, floor included. */
async function painted(): Promise<void> {
	await vi.advanceTimersByTimeAsync(PAINT_FLOOR_MS + 20);
}

/** The image a key was last given. */
function lastImage(key: FakeKey): string {
	const call = key.setImage.mock.calls.at(-1);
	expect(call, "the key was never drawn").toBeDefined();

	return decodeImage(call![0]);
}

describe("FaceKey", () => {
	let deps: ReturnType<typeof fakeDeps>;
	let action: InstanceType<typeof FaceKey>;

	beforeEach(() => {
		vi.useFakeTimers();
		deps = fakeDeps();
		action = new FaceKey(deps);
	});

	afterEach(() => {
		action.stop();
		vi.useRealTimers();
	});

	/** Shows a key at a tile, and registers it with the action under test. */
	async function place(key: FakeKey, column: number, row: number, settings: object = {}): Promise<void> {
		(action as unknown as { actions: unknown[] }).actions.push(key);
		await appear(action, key, settings, { column, row });
	}

	it("answers to the action identifier from the manifest", () => {
		expect(action.manifestId).toBe("com.okonoma.claudio.face");
		expect(FACE_UUID).toBe("com.okonoma.claudio.face");
	});

	it("draws its own window onto the face, at the tile it was placed on", async () => {
		deps.store.update({ connected: true, state: IDLE });
		const key = fakeKey("key-eye", "deck-red");

		await place(key, 3, 1);
		await painted();

		expect(lastImage(key)).toBe(tileSvg(faceSvg(RESTING), 3, 1));
	});

	it("redraws only the tiles the change actually touches", async () => {
		deps.store.update({ connected: true, state: IDLE });
		const eye = fakeKey("key-eye", "deck-red");
		const antenna = fakeKey("key-antenna", "deck-red");
		await place(eye, 1, 1);
		await place(antenna, 2, 0);
		await painted();
		eye.setImage.mockClear();
		antenna.setImage.mockClear();

		deps.store.setState({ ...IDLE, gaze: "fait" });
		await painted();

		expect(lastImage(eye)).toBe(tileSvg(faceSvg({ ...RESTING, gaze: "fait" }), 1, 1));
		expect(antenna.setImage).not.toHaveBeenCalled();
	});

	it("keeps two decks' boards apart, even at the same coordinates", async () => {
		deps.store.update({ connected: true, state: IDLE });
		const red = fakeKey("key-red", "deck-red");
		const blue = fakeKey("key-blue", BLUE);
		await place(red, 1, 1);
		await place(blue, 1, 1);
		await painted();
		red.setImage.mockClear();
		blue.setImage.mockClear();

		deps.store.setState({ ...IDLE, gaze: "veille" });
		await painted();

		expect(lastImage(red)).toBe(tileSvg(faceSvg({ ...RESTING, gaze: "veille" }), 1, 1));
		expect(lastImage(blue)).toBe(tileSvg(faceSvg({ ...RESTING, gaze: "veille" }), 1, 1));
	});

	it("shows an empty gaze, no glow, and the way back, while nobody answers", async () => {
		const key = fakeKey("key-message", "deck-red");

		await place(key, 2, 1);
		await painted();

		const expected: FaceParams = {
			gaze: "vide",
			level: 0,
			glow: false,
			disconnected: true,
			message: "[face.disconnected.message]",
		};
		expect(lastImage(key)).toBe(tileSvg(faceSvg(expected), 2, 1));
	});

	it("blinks while he is waiting, and only then", async () => {
		deps.store.update({ connected: true, state: IDLE });
		const key = fakeKey("key-eye", "deck-red");
		await place(key, 1, 1);

		// The eyes close after the shortest pace, since the suite pins the pace down.
		await vi.advanceTimersByTimeAsync(BLINK_MIN_MS + 50);

		expect(lastImage(key)).toBe(tileSvg(faceSvg({ ...RESTING, gaze: "veille" }), 1, 1));

		await vi.advanceTimersByTimeAsync(BLINK_CLOSED_MS);

		expect(lastImage(key)).toBe(tileSvg(faceSvg(RESTING), 1, 1));
	});

	it("does not blink at a deck nobody answers", async () => {
		const key = fakeKey("key-eye", "deck-red");
		await place(key, 1, 1);
		await painted();
		key.setImage.mockClear();

		await vi.advanceTimersByTimeAsync(BLINK_MIN_MS * 3);
		await painted();

		expect(key.setImage).not.toHaveBeenCalled();
	});

	it("coalesces level frames rather than redrawing on every one of them", async () => {
		deps.store.update({ connected: true, state: IDLE });
		const key = fakeKey("key-moustache", "deck-red");
		await place(key, 0, 2);
		await painted();
		key.setImage.mockClear();

		deps.hear(0.4);
		deps.hear(0.6);
		deps.hear(0.9);
		await painted();

		expect(key.setImage).toHaveBeenCalledTimes(1);
		expect(lastImage(key)).toBe(tileSvg(faceSvg({ ...RESTING, level: 0.4 }), 0, 2));

		await vi.advanceTimersByTimeAsync(LEVEL_COALESCE_MS);
		await painted();

		expect(lastImage(key)).toBe(tileSvg(faceSvg({ ...RESTING, level: 0.9 }), 0, 2));
	});

	it("takes the deck to the actions page when a tile is pressed", async () => {
		deps.store.update({ connected: true, state: IDLE });
		const key = fakeKey("key-1", "deck-red");
		await place(key, 4, 2);

		await press(action, key);

		expect(deps.touch).toHaveBeenCalledWith("deck-red");
		expect(deps.showActions).toHaveBeenCalledWith("deck-red");
	});

	it("opens Claudio instead of navigating when nobody answers", async () => {
		const key = fakeKey("key-1", "deck-red");
		await place(key, 4, 2);

		await press(action, key);

		expect(deps.showActions).not.toHaveBeenCalled();
		expect(key.showAlert).toHaveBeenCalledOnce();
		expect(deps.openClaudio).toHaveBeenCalledOnce();
	});

	it("says the deck is home, and reads the delay it was told to keep", async () => {
		const key = fakeKey("key-1", "deck-red");

		await place(key, 0, 0, { idleSeconds: "120" });

		expect(deps.sawFace).toHaveBeenCalledWith("deck-red");
		expect(deps.setIdleSeconds).toHaveBeenCalledWith(120);
	});

	it("rests on the usual delay when a tile carries none", async () => {
		const key = fakeKey("key-1", "deck-red");

		await place(key, 0, 0);

		expect(deps.setIdleSeconds).toHaveBeenCalledWith(DEFAULT_IDLE_SECONDS);
	});

	it("carries a changed delay to every other tile of the board", async () => {
		const first = fakeKey("key-1", "deck-red");
		const second = fakeKey("key-2", "deck-red");
		await place(first, 0, 0);
		await place(second, 0, 1);
		deps.setIdleSeconds.mockClear();

		await action.onDidReceiveSettings?.({
			action: first,
			payload: { settings: { idleSeconds: "30" } },
		} as never);

		expect(deps.setIdleSeconds).toHaveBeenCalledWith(30);
		expect(second.setSettings).toHaveBeenCalledWith({ idleSeconds: 30 });
		expect(first.setSettings).not.toHaveBeenCalled();
	});

	it("stops drawing a tile that left the page", async () => {
		deps.store.update({ connected: true, state: IDLE });
		const key = fakeKey("key-1", "deck-red");
		await place(key, 1, 1);
		await painted();
		key.setImage.mockClear();

		await disappear(action, key);
		(action as unknown as { actions: unknown[] }).actions = [];
		deps.store.setState({ ...IDLE, gaze: "fait" });
		await painted();

		expect(key.setImage).not.toHaveBeenCalled();
	});
});
