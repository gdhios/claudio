import { beforeEach, describe, expect, it, vi } from "vitest";

// The real SDK opens a log file and installs process handlers the moment it is imported;
// the keys only need the base class and the decorator's job, which this stands in for.
vi.mock("@elgato/streamdeck", () => ({
	SingletonAction: class {
		public actions: unknown[] = [];
	},
}));

const { ACTION_UUID, ClaudioActionKey, DEFAULT_ACTION_ID } = await import("../src/actions/action.js");
const { WINDOW_UUID, WindowKey, DEFAULT_WINDOW_LAYOUT } = await import("../src/actions/window.js");
const { mascot, musicNote, textCorrect, tie, windowLayout } = await import("../src/render/glyphs.js");
const { PAINT_FLOOR_MS } = await import("../src/actions/keys.js");
const { followBridge } = await import("../src/state/follow.js");
const { Store } = await import("../src/state/store.js");
const { decodeImage, fakeBridgeFeed } = await import("./fakes.js");

type FakeKey = ReturnType<typeof fakeKey>;

/** The deck every fake key of these suites sits on. */
const DECK = "deck-red";

/** A key on the hardware, as far as an action can tell. */
function fakeKey(id = "key-1") {
	return {
		id,
		device: { id: DECK },
		isKey: () => true,
		setImage: vi.fn(async (_image: string) => {}),
		setTitle: vi.fn(async (_title: string) => {}),
		showAlert: vi.fn(async () => {}),
		showOk: vi.fn(async () => {}),
	};
}

/** The collaborators both keys are built with. */
function fakeDeps() {
	return {
		bridge: { send: vi.fn(() => true) },
		store: new Store(),
		openClaudio: vi.fn(async () => {}),
		touch: vi.fn(),
		translate: (key: string) => `[${key}]`,
	};
}

/**
 * Plays Stream Deck showing a key.
 * @param action Action under test.
 * @param key The key.
 * @param settings Settings the key carries.
 */
async function appear(
	action: { onWillAppear?: (ev: never) => Promise<void> | void },
	key: FakeKey,
	settings: object,
): Promise<void> {
	await action.onWillAppear?.({ action: key, payload: { settings } } as never);
}

/**
 * Plays a press.
 * @param action Action under test.
 * @param key The key.
 * @param settings Settings the key carries.
 */
async function press(
	action: { onKeyDown?: (ev: never) => Promise<void> | void },
	key: FakeKey,
	settings: object,
): Promise<void> {
	await action.onKeyDown?.({ action: key, payload: { settings } } as never);
}

/** Lets every redraw a store change started run to the end. */
function settle(): Promise<void> {
	return new Promise((resolve) => setTimeout(resolve, 0));
}

/** Lets the painter's floor pass, so a drawing it is holding back goes out. */
function painted(): Promise<void> {
	return new Promise((resolve) => setTimeout(resolve, PAINT_FLOOR_MS + 20));
}

/** The image the key was last given. */
function lastImage(key: FakeKey): string {
	const call = key.setImage.mock.calls.at(-1);
	expect(call, "the key was never drawn").toBeDefined();

	return decodeImage(call![0]);
}

describe("ClaudioActionKey", () => {
	let deps: ReturnType<typeof fakeDeps>;
	let action: InstanceType<typeof ClaudioActionKey>;
	let key: FakeKey;

	beforeEach(() => {
		deps = fakeDeps();
		action = new ClaudioActionKey(deps);
		key = fakeKey();
		(action as unknown as { actions: unknown[] }).actions = [key];
	});

	it("answers to the action identifier from the manifest", () => {
		expect(action.manifestId).toBe("com.okonoma.claudio.action");
		expect(ACTION_UUID).toBe("com.okonoma.claudio.action");
	});

	it("corrects, until told otherwise", () => {
		expect(DEFAULT_ACTION_ID).toBe("correct");
	});

	it("puts off the deck's return to the face on every press", async () => {
		deps.store.setConnected(true);

		await press(action, key, {});

		expect(deps.touch).toHaveBeenCalledWith("deck-red");
	});

	it("draws the glyph and the label of the action it carries", async () => {
		deps.store.setConnected(true);

		await appear(action, key, { id: "professionalTone" });
		await painted();

		expect(lastImage(key)).toContain(tie());
		expect(lastImage(key)).toContain(">[action.professionalTone.label]<");
	});

	it("draws a music note for What's playing?", async () => {
		deps.store.setConnected(true);

		await appear(action, key, { id: "whatsPlaying" });
		await painted();

		expect(lastImage(key)).toContain(musicNote());
		expect(lastImage(key)).toContain(">[action.whatsPlaying.label]<");
	});

	it("clears the Stream Deck title, which would sit on top of the drawing", async () => {
		await appear(action, key, { id: "correct" });

		expect(key.setTitle).toHaveBeenCalledWith("");
	});

	it("falls back to correcting when it carries no setting", async () => {
		deps.store.setConnected(true);

		await appear(action, key, {});
		await painted();

		expect(lastImage(key)).toContain(textCorrect());
	});

	it("fades while there is nobody to talk to", async () => {
		await appear(action, key, { id: "correct" });

		expect(lastImage(key)).toContain('opacity="0.45"');
	});

	it("sends the action it carries when pressed", async () => {
		deps.store.setConnected(true);

		await press(action, key, { id: "summarize" });

		expect(deps.bridge.send).toHaveBeenCalledWith({ type: "action", id: "summarize" });
	});

	it("sends nothing while disconnected, and says so", async () => {
		await press(action, key, { id: "summarize" });

		expect(deps.bridge.send).not.toHaveBeenCalled();
		expect(key.showAlert).toHaveBeenCalledOnce();
		expect(deps.openClaudio).toHaveBeenCalledOnce();
	});

	it("shows the mascot keeping watch while a correction streams", async () => {
		deps.store.setConnected(true);
		await appear(action, key, { id: "correct" });

		deps.store.setState({
			gaze: "veille",
			activity: "correction",
			phase: "streaming",
			label: "Correction…",
			locked: false,
		});
		await vi.waitFor(() => expect(lastImage(key)).toContain(mascot("veille")));

		expect(lastImage(key)).not.toContain(textCorrect());
	});

	it("keeps its own glyph when the work is a dictation, not a correction", async () => {
		deps.store.setConnected(true);
		await appear(action, key, { id: "correct" });
		deps.store.setState({ gaze: "veille", activity: "correction", phase: "streaming", label: null, locked: false });
		await vi.waitFor(() => expect(lastImage(key)).toContain(mascot("veille")));

		// The same phase, another activity: the mascot belongs to the correction alone.
		deps.store.setState({ gaze: "veille", activity: "dictation", phase: "streaming", label: null, locked: true });

		await vi.waitFor(() => expect(lastImage(key)).toContain(textCorrect()));
	});

	it("ticks the key that was pressed, once the correction lands", async () => {
		deps.store.setConnected(true);
		await appear(action, key, { id: "correct" });
		await press(action, key, { id: "correct" });
		streams();

		lands();

		await vi.waitFor(() => expect(key.showOk).toHaveBeenCalledOnce());
	});

	it("ticks nothing when the correction was not started from a key", async () => {
		deps.store.setConnected(true);
		await appear(action, key, { id: "correct" });
		streams();

		lands();

		await settle();
		expect(key.showOk).not.toHaveBeenCalled();
	});

	it("ticks only the key that was pressed, not every Claudio key on the deck", async () => {
		const other = fakeKey("key-2");
		(action as unknown as { actions: unknown[] }).actions = [key, other];
		deps.store.setConnected(true);
		await appear(action, key, { id: "correct" });
		await appear(action, other, { id: "summarize" });
		await press(action, other, { id: "summarize" });
		streams();

		lands();

		await vi.waitFor(() => expect(other.showOk).toHaveBeenCalledOnce());
		expect(key.showOk).not.toHaveBeenCalled();
	});

	it("ticks once per press, not once per correction that ends", async () => {
		deps.store.setConnected(true);
		await appear(action, key, { id: "correct" });
		await press(action, key, { id: "correct" });
		streams();
		lands();
		await vi.waitFor(() => expect(key.showOk).toHaveBeenCalledOnce());

		streams();
		lands();

		await settle();
		expect(key.showOk).toHaveBeenCalledOnce();
	});

	it("still ticks a correction that follows a dictation", async () => {
		deps.store.setConnected(true);
		await appear(action, key, { id: "correct" });
		await press(action, key, { id: "correct" });
		streams();
		// A dictation runs its own course, ending on its own `done`, between the two.
		deps.store.setState({ gaze: "veille", activity: "dictation", phase: "listening", label: null, locked: true });
		deps.store.setState({ gaze: "fait", activity: "dictation", phase: "done", label: null, locked: false });
		await settle();
		// That `done` was the dictation's, and must not be taken for the correction's.
		expect(key.showOk).not.toHaveBeenCalled();

		lands();

		await vi.waitFor(() => expect(key.showOk).toHaveBeenCalledOnce());
	});

	it("returns to its own glyph when Claudio goes away mid-correction", async () => {
		const bridge = fakeBridgeFeed();
		followBridge(bridge.feed, deps.store);
		bridge.emit("connected", { gaze: "repos", activity: "idle", phase: null, label: null, locked: false });
		await appear(action, key, { id: "correct" });
		bridge.emit("state", { gaze: "veille", activity: "correction", phase: "streaming", label: null, locked: false });
		await vi.waitFor(() => expect(lastImage(key)).toContain(mascot("veille")));

		bridge.emit("disconnected");

		// The correction cannot still be streaming: there is nobody left to stream it.
		await vi.waitFor(() => expect(lastImage(key)).toContain(textCorrect()));
	});

	it("warns when the frame could not go out after all", async () => {
		deps.store.setConnected(true);
		deps.bridge.send.mockReturnValue(false);

		await press(action, key, { id: "correct" });

		expect(key.showAlert).toHaveBeenCalledOnce();
	});

	it("remembers no press from a key that could not send", async () => {
		deps.store.setConnected(true);
		deps.bridge.send.mockReturnValue(false);
		await press(action, key, { id: "correct" });
		deps.bridge.send.mockReturnValue(true);
		streams();

		lands();

		await settle();
		expect(key.showOk).not.toHaveBeenCalled();
	});

	it("ticks nothing after What's playing?, which starts no correction", async () => {
		deps.store.setConnected(true);
		await appear(action, key, { id: "whatsPlaying" });
		await press(action, key, { id: "whatsPlaying" });
		// The correction that follows comes from the keyboard: it is nobody's to tick.
		streams();

		lands();

		await settle();
		expect(key.showOk).not.toHaveBeenCalled();
	});

	it("owes no key a tick once What's playing? has closed the correction in flight", async () => {
		const listen = fakeKey("key-2");
		(action as unknown as { actions: unknown[] }).actions = [key, listen];
		deps.store.setConnected(true);
		await appear(action, key, { id: "correct" });
		await appear(action, listen, { id: "whatsPlaying" });
		await press(action, key, { id: "correct" });
		streams();
		// The app makes room for its listening panel: that correction never lands.
		await press(action, listen, { id: "whatsPlaying" });
		deps.store.setState({ gaze: "repos", activity: "idle", phase: null, label: null, locked: false });
		// The next one comes from the keyboard.
		streams();

		lands();

		await settle();
		expect(key.showOk).not.toHaveBeenCalled();
		expect(listen.showOk).not.toHaveBeenCalled();
	});

	it("forgets the press of a key that left the page", async () => {
		deps.store.setConnected(true);
		await appear(action, key, { id: "correct" });
		await press(action, key, { id: "correct" });

		action.onWillDisappear?.({ action: key } as never);
		streams();
		lands();

		await settle();
		expect(key.showOk).not.toHaveBeenCalled();
	});

	/** Plays a correction streaming. */
	function streams(): void {
		deps.store.setState({ gaze: "veille", activity: "correction", phase: "streaming", label: null, locked: false });
	}

	/** Plays that correction landing. */
	function lands(): void {
		deps.store.setState({ gaze: "fait", activity: "correction", phase: "done", label: null, locked: false });
	}

	it("leaves the key alone when it is a dictation that finished", async () => {
		deps.store.setConnected(true);
		await appear(action, key, { id: "correct" });
		deps.store.setState({ gaze: "repos", activity: "dictation", phase: "cleaning", label: null, locked: true });
		await settle();

		deps.store.setState({ gaze: "fait", activity: "dictation", phase: "done", label: null, locked: false });
		await settle();

		expect(key.showOk).not.toHaveBeenCalled();
	});

	it("draws a key only when the drawing actually changed", async () => {
		deps.store.setConnected(true);
		await appear(action, key, { id: "correct" });
		const drawn = key.setImage.mock.calls.length;

		deps.store.setState({ gaze: "repos", activity: "idle", phase: null, label: null, locked: false });
		deps.store.setState({ gaze: "repos", activity: "idle", phase: null, label: "Prêt", locked: false });
		await settle();

		expect(key.setImage.mock.calls.length).toBe(drawn);
	});

	it("draws a key again from scratch after it left the page and came back", async () => {
		await appear(action, key, { id: "correct" });
		const drawn = key.setImage.mock.calls.length;

		action.onWillDisappear?.({ action: key } as never);
		await appear(action, key, { id: "correct" });

		expect(key.setImage.mock.calls.length).toBe(drawn + 1);
	});
});

describe("WindowKey", () => {
	let deps: ReturnType<typeof fakeDeps>;
	let action: InstanceType<typeof WindowKey>;
	let key: FakeKey;

	beforeEach(() => {
		deps = fakeDeps();
		action = new WindowKey(deps);
		key = fakeKey();
		(action as unknown as { actions: unknown[] }).actions = [key];
	});

	it("answers to the window identifier from the manifest", () => {
		expect(action.manifestId).toBe("com.okonoma.claudio.window");
		expect(WINDOW_UUID).toBe("com.okonoma.claudio.window");
	});

	it("takes the left half, until told otherwise", () => {
		expect(DEFAULT_WINDOW_LAYOUT).toBe("leftHalf");
	});

	it("puts off the deck's return to the face on every press", async () => {
		deps.store.setConnected(true);

		await press(action, key, {});

		expect(deps.touch).toHaveBeenCalledWith("deck-red");
	});

	it("draws its layout on the dark background, with no label", async () => {
		deps.store.setConnected(true);

		await appear(action, key, { layout: "bottomRight" });
		await painted();

		expect(lastImage(key)).toContain(windowLayout("bottomRight"));
		expect(lastImage(key)).toContain("#120E1C");
		expect(lastImage(key)).not.toContain("<text");
	});

	it("sends the layout it carries when pressed", async () => {
		deps.store.setConnected(true);

		await press(action, key, { layout: "nextScreen" });

		expect(deps.bridge.send).toHaveBeenCalledWith({ type: "window", layout: "nextScreen" });
	});

	it("sends nothing while disconnected, and says so", async () => {
		await press(action, key, { layout: "nextScreen" });

		expect(deps.bridge.send).not.toHaveBeenCalled();
		expect(key.showAlert).toHaveBeenCalledOnce();
		expect(deps.openClaudio).toHaveBeenCalledOnce();
	});

	it("warns when the frame could not go out after all", async () => {
		deps.store.setConnected(true);
		deps.bridge.send.mockReturnValue(false);

		await press(action, key, { layout: "nextScreen" });

		expect(key.showAlert).toHaveBeenCalledOnce();
	});
});
