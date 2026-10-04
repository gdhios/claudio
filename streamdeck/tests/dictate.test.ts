import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// The real SDK opens a log file and installs process handlers the moment it is imported;
// the key only needs the base class and the decorator's job, which this stands in for.
vi.mock("@elgato/streamdeck", () => ({
	SingletonAction: class {
		public actions: unknown[] = [];
	},
}));

const { parseOutbound } = await import("../src/bridge/protocol.js");
const { dictateLook } = await import("../src/render/dictate.js");
const { mascot, micGlyph } = await import("../src/render/glyphs.js");
const { DEFAULT_LANGUAGE, DEFAULT_OUTPUT, DICTATE_UUID, DictateKey } = await import("../src/actions/dictate.js");
const { LevelMeter, METER_WINDOW_MS } = await import("../src/actions/meter.js");
const { followBridge } = await import("../src/state/follow.js");
const { Store } = await import("../src/state/store.js");
const { decodeImage, fakeBridgeFeed } = await import("./fakes.js");

type BridgeState = import("../src/bridge/protocol.js").BridgeState;

const fixturesDir = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "protocol", "fixtures");

/**
 * Reads a state the app sends, through the same parser the plugin uses.
 * @param name Name of the fixture.
 * @returns The state it carries.
 */
function stateFixture(name: string): BridgeState {
	const frame = parseOutbound(readFileSync(path.join(fixturesDir, `${name}.json`), "utf8"));
	expect(frame.type, `${name} is not a state frame`).toBe("state");
	const { type: _type, ...state } = frame as { type: "state" } & BridgeState;

	return state;
}

/** Translates the way the plugin does, but visibly. */
function translate(key: string): string {
	return `[${key}]`;
}

/**
 * Asks what a key shows at a given moment.
 * @param state The app's state, or `null` when the key follows nothing.
 * @param levels The levels last heard.
 * @returns The look.
 */
function look(state: BridgeState | null, levels: readonly number[] = []) {
	return dictateLook({ state, levels, restLabel: "Dicter", translate });
}

describe("dictateLook", () => {
	it("rests on the label of its own settings while nothing is being dictated", () => {
		expect(look(null)).toEqual({ state: "rest", glyph: micGlyph(), label: "Dicter" });
	});

	it("rests while the app is busy with something that is not a dictation", () => {
		expect(look(stateFixture("state-correction-streaming")).state).toBe("rest");
		expect(look(stateFixture("state-idle")).state).toBe("rest");
	});

	it("asks the user to speak, and shows what it hears", () => {
		const shown = look(stateFixture("state-dictation-listening"), [0.2, 0.7]);

		expect(shown.state).toBe("listening");
		expect(shown.label).toBe("[dictate.listening]");
		expect(shown.glyph).toBe(micGlyph({ levels: [0.2, 0.7] }));
	});

	it("padlocks a dictation that was locked hands-free", () => {
		const listening = stateFixture("state-dictation-listening");
		const shown = look({ ...listening, locked: true }, [0.4]);

		expect(shown.state).toBe("locked");
		expect(shown.label).toBe("[dictate.locked]");
		expect(shown.glyph).toBe(micGlyph({ levels: [0.4], locked: true }));
	});

	it("keeps watch, in the app's own words, while it works on what was said", () => {
		const shown = look(stateFixture("state-dictation-cleaning-locked"));

		expect(shown.state).toBe("working");
		expect(shown.glyph).toBe(mascot("veille"));
		// The app names the step it is on, in its own language; that beats a guess.
		expect(shown.label).toBe("Nettoyage…");
	});

	it("says it is working when the app says nothing", () => {
		const cleaning = stateFixture("state-dictation-cleaning-locked");

		for (const phase of ["finishing", "cleaning", "pasting"]) {
			const shown = look({ ...cleaning, phase, label: null });

			expect(shown.state, phase).toBe("working");
			expect(shown.label, phase).toBe("[dictate.working]");
		}
	});

	it("smiles once the text has landed", () => {
		const shown = look(stateFixture("state-dictation-done"));

		expect(shown.state).toBe("done");
		expect(shown.glyph).toBe(mascot("fait"));
		expect(shown.label).toBe("[dictate.done]");
	});

	it.each(["state-dictation-empty", "state-dictation-error"])(
		"goes back to resting on %s, where nothing was pasted",
		(name) => {
			expect(look(stateFixture(name))).toEqual({ state: "rest", glyph: micGlyph(), label: "Dicter" });
		},
	);

	it("rests on a phase it does not know", () => {
		const listening = stateFixture("state-dictation-listening");

		expect(look({ ...listening, phase: "somethingNew" }).state).toBe("rest");
	});
});

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

/** The collaborators the key is built with, plus a way to play the level frames. */
function fakeDeps() {
	const listeners = new Set<(value: number) => void>();

	return {
		bridge: { send: vi.fn(() => true) },
		store: new Store(),
		openClaudio: vi.fn(async () => {}),
		touch: vi.fn(),
		translate,
		onLevel: (listener: (value: number) => void): (() => void) => {
			listeners.add(listener);

			return () => listeners.delete(listener);
		},
		/** Plays a level frame arriving from the app. */
		hears: (...levels: number[]): void => {
			for (const level of levels) {
				for (const listener of [...listeners]) {
					listener(level);
				}
			}
		},
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
async function hold(
	action: { onKeyDown?: (ev: never) => Promise<void> | void },
	key: FakeKey,
	settings: object = {},
): Promise<void> {
	await action.onKeyDown?.({ action: key, payload: { settings } } as never);
}

/**
 * Plays a release.
 * @param action Action under test.
 * @param key The key.
 * @param settings Settings the key carries.
 */
async function release(
	action: { onKeyUp?: (ev: never) => Promise<void> | void },
	key: FakeKey,
	settings: object = {},
): Promise<void> {
	await action.onKeyUp?.({ action: key, payload: { settings } } as never);
}

/** The image the key was last given. */
function lastImage(key: FakeKey): string {
	const call = key.setImage.mock.calls.at(-1);
	expect(call, "the key was never drawn").toBeDefined();

	return decodeImage(call![0]);
}

describe("DictateKey", () => {
	let deps: ReturnType<typeof fakeDeps>;
	let action: InstanceType<typeof DictateKey>;
	let key: FakeKey;

	beforeEach(() => {
		// The meter and the moment a finished dictation fades are both timed; nothing here
		// waits on a real clock.
		vi.useFakeTimers();
		deps = fakeDeps();
		action = new DictateKey(deps);
		key = fakeKey();
		(action as unknown as { actions: unknown[] }).actions = [key];
	});

	afterEach(() => {
		vi.useRealTimers();
	});

	/** Lets every redraw a change started run to the end. */
	async function settle(): Promise<void> {
		for (let tick = 0; tick < 5; tick++) {
			await vi.advanceTimersByTimeAsync(0);
		}
	}

	/** Lets time pass, redraws and all. */
	async function after(milliseconds: number): Promise<void> {
		await vi.advanceTimersByTimeAsync(milliseconds);
		await settle();
	}

	/** Plays the app saying what it is doing. */
	async function says(phase: string | null, extra: Partial<BridgeState> = {}): Promise<void> {
		deps.store.setState({
			gaze: "repos",
			activity: phase === null ? "idle" : "dictation",
			phase,
			label: null,
			locked: false,
			...extra,
		});
		await settle();
	}

	it("answers to the action identifier from the manifest", () => {
		expect(action.manifestId).toBe("com.okonoma.claudio.dictate");
		expect(DICTATE_UUID).toBe("com.okonoma.claudio.dictate");
	});

	it("dictates in the main language and cleans the text up, until told otherwise", () => {
		expect(DEFAULT_LANGUAGE).toBe("primary");
		expect(DEFAULT_OUTPUT).toBe("cleanup");
	});

	it("puts off the deck's return to the face on every press", async () => {
		deps.store.setConnected(true);

		await hold(action, key);

		expect(deps.touch).toHaveBeenCalledWith("deck-red");
	});

	it("starts dictating while the key is held, and stops when it comes up", async () => {
		deps.store.setConnected(true);

		await hold(action, key);
		await release(action, key);

		expect(deps.bridge.send).toHaveBeenNthCalledWith(1, {
			type: "dictation",
			event: "down",
			language: "primary",
			output: "cleanup",
		});
		expect(deps.bridge.send).toHaveBeenNthCalledWith(2, { type: "dictation", event: "up" });
	});

	it("dictates in the language and to the output its settings name", async () => {
		deps.store.setConnected(true);

		await hold(action, key, { language: "secondary", output: "translateEN" });

		expect(deps.bridge.send).toHaveBeenCalledWith({
			type: "dictation",
			event: "down",
			language: "secondary",
			output: "translateEN",
		});
	});

	it("lets go whatever the app was doing", async () => {
		deps.store.setConnected(true);
		await hold(action, key);
		await says("cleaning");
		deps.bridge.send.mockClear();

		await release(action, key);

		expect(deps.bridge.send).toHaveBeenCalledWith({ type: "dictation", event: "up" });
	});

	it("sends nothing while disconnected, and says so", async () => {
		await hold(action, key);

		expect(deps.bridge.send).not.toHaveBeenCalled();
		expect(key.showAlert).toHaveBeenCalledOnce();
		expect(deps.openClaudio).toHaveBeenCalledOnce();
	});

	it("says nothing twice when the key it could not start comes up", async () => {
		await hold(action, key);

		await release(action, key);

		expect(deps.bridge.send).not.toHaveBeenCalled();
		expect(key.showAlert).toHaveBeenCalledOnce();
	});

	it("sends no release for a press that never started anything", async () => {
		// The key was pressed with nobody there; the bridge comes up while it is still held.
		await hold(action, key);
		deps.store.setConnected(true);

		await release(action, key);

		expect(deps.bridge.send, "an `up` on its own would stop a dictation nobody started").not.toHaveBeenCalled();
	});

	it("warns when the release could not go out after all", async () => {
		deps.store.setConnected(true);
		await hold(action, key);
		deps.bridge.send.mockReturnValue(false);

		await release(action, key);

		expect(key.showAlert).toHaveBeenCalledOnce();
	});

	it("forgets a press the bridge refused, however old the last one is", async () => {
		deps.store.setConnected(true);
		await appear(action, key, {});
		await hold(action, key);
		await release(action, key);
		deps.bridge.send.mockReturnValue(false);

		await hold(action, key);
		deps.bridge.send.mockReturnValue(true);
		await says("error", { gaze: "vide" });

		// One warning, for the press that was refused — not a second for a dictation
		// this key never started.
		expect(key.showAlert).toHaveBeenCalledOnce();
	});

	it("keeps one key's press when another key is released", async () => {
		const other = fakeKey("key-2");
		(action as unknown as { actions: unknown[] }).actions = [key, other];
		deps.store.setConnected(true);
		await appear(action, key, {});
		await appear(action, other, {});
		await hold(action, key);

		// The bridge drops while the key is held, and the other key is the one let go.
		deps.store.setConnected(false);
		await release(action, other);
		deps.store.setConnected(true);
		await says("error", { gaze: "vide" });

		expect(key.showAlert).toHaveBeenCalledOnce();
		expect(other.showAlert).not.toHaveBeenCalled();
	});

	it("warns when the frame could not go out after all", async () => {
		deps.store.setConnected(true);
		deps.bridge.send.mockReturnValue(false);

		await hold(action, key);

		expect(key.showAlert).toHaveBeenCalledOnce();
	});

	it("draws the label of the output it carries", async () => {
		deps.store.setConnected(true);

		await appear(action, key, { output: "makePrompt" });
		await after(200);

		expect(lastImage(key)).toContain(">[dictate.makePrompt.label]<");
		expect(lastImage(key)).toContain('data-state="rest"');
	});

	it("clears the Stream Deck title, which would sit on top of the drawing", async () => {
		await appear(action, key, {});

		expect(key.setTitle).toHaveBeenCalledWith("");
	});

	it("fades while there is nobody to talk to", async () => {
		await appear(action, key, {});

		expect(lastImage(key)).toContain('opacity="0.45"');
	});

	it("shows the same dictation on every key of the page", async () => {
		const other = fakeKey("key-2");
		(action as unknown as { actions: unknown[] }).actions = [key, other];
		deps.store.setConnected(true);
		await appear(action, key, {});
		await appear(action, other, { output: "translateEN" });

		await says("listening");
		await after(200);

		expect(lastImage(key)).toContain('data-state="listening"');
		expect(lastImage(other)).toContain('data-state="listening"');
	});

	it("draws the level it has just heard", async () => {
		deps.store.setConnected(true);
		await appear(action, key, {});
		await says("listening");

		deps.hears(0.8);
		await after(200);

		expect(lastImage(key)).toContain(micGlyph({ levels: [0.8] }));
	});

	it("redraws a key eight times a second at most, however fast the levels arrive", async () => {
		deps.store.setConnected(true);
		await appear(action, key, {});
		await says("listening");
		await after(200);
		const drawn = key.setImage.mock.calls.length;

		// Forty frames in a second: five times what the app actually sends.
		for (let frame = 0; frame < 40; frame++) {
			deps.hears(frame / 40);
			await after(25);
		}

		expect(key.setImage.mock.calls.length - drawn).toBeLessThanOrEqual(9);
	});

	it("shows the seven levels it heard last", async () => {
		deps.store.setConnected(true);
		await appear(action, key, {});
		await says("listening");

		for (const level of [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]) {
			deps.hears(level);
			await after(125);
		}

		expect(lastImage(key)).toContain(micGlyph({ levels: [0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9] }));
	});

	it("hears nothing while the app is not listening", async () => {
		deps.store.setConnected(true);
		await appear(action, key, {});
		await says("cleaning");
		await after(200);
		const drawn = key.setImage.mock.calls.length;

		// A level that arrives late, while the app is already cleaning up, is not this
		// dictation's and not the next one's either.
		deps.hears(0.9);
		await after(125);
		expect(key.setImage.mock.calls.length, "nothing to redraw for it").toBe(drawn);

		await says("listening");

		expect(lastImage(key)).toContain(micGlyph({ levels: [] }));
	});

	it("starts the next dictation on an empty meter", async () => {
		deps.store.setConnected(true);
		await appear(action, key, {});
		await says("listening");
		deps.hears(0.9);
		await after(125);
		await says("done");

		await says("listening");
		await after(200);

		expect(lastImage(key)).toContain(micGlyph({ levels: [] }));
	});

	it("shows the text landing, then goes back to resting", async () => {
		deps.store.setConnected(true);
		await appear(action, key, { output: "cleanup" });

		await says("done");
		await after(200);
		expect(lastImage(key)).toContain('data-state="done"');
		expect(lastImage(key)).toContain(mascot("fait"));

		await after(1200);
		expect(lastImage(key), "it lingers on the text that landed").toContain('data-state="done"');

		await after(300);
		expect(lastImage(key)).toContain('data-state="rest"');
		expect(lastImage(key)).toContain(">[dictate.cleanup.label]<");
	});

	it("does not go back to resting over a dictation that has already started again", async () => {
		deps.store.setConnected(true);
		await appear(action, key, {});
		await says("done");

		await after(500);
		await says("listening");
		await after(1500);

		expect(lastImage(key)).toContain('data-state="listening"');
	});

	it("warns the key that started a dictation that came to nothing", async () => {
		deps.store.setConnected(true);
		await appear(action, key, {});
		await hold(action, key);
		await release(action, key);

		await says("empty", { gaze: "vide" });

		expect(key.showAlert).toHaveBeenCalledOnce();
		expect(lastImage(key)).toContain('data-state="rest"');
	});

	it("warns the key that started a dictation that failed", async () => {
		deps.store.setConnected(true);
		await appear(action, key, {});
		await hold(action, key);

		await says("error", { gaze: "vide" });

		expect(key.showAlert).toHaveBeenCalledOnce();
	});

	it("warns once, not on every frame that follows", async () => {
		deps.store.setConnected(true);
		await appear(action, key, {});
		await hold(action, key);
		await says("error", { gaze: "vide" });

		await says("error", { gaze: "vide", label: "Erreur" });

		expect(key.showAlert).toHaveBeenCalledOnce();
	});

	it("warns nobody when the text landed, since the key already says so", async () => {
		deps.store.setConnected(true);
		await appear(action, key, {});
		await hold(action, key);
		await release(action, key);

		await says("done");

		expect(key.showAlert).not.toHaveBeenCalled();
	});

	it("does not start the wait over when the app repeats itself", async () => {
		deps.store.setConnected(true);
		await appear(action, key, {});
		await says("done");

		await after(1000);
		await says("done", { label: "Collé" });
		await after(600);

		expect(lastImage(key)).toContain('data-state="rest"');
	});

	it("warns nobody when the dictation was not started from a key", async () => {
		deps.store.setConnected(true);
		await appear(action, key, {});

		await says("empty", { gaze: "vide" });

		expect(key.showAlert).not.toHaveBeenCalled();
	});

	it("warns nobody once the key that started the dictation has left the page", async () => {
		deps.store.setConnected(true);
		await appear(action, key, {});
		await hold(action, key);

		action.onWillDisappear?.({ action: key } as never);
		await says("error", { gaze: "vide" });

		expect(key.showAlert).not.toHaveBeenCalled();
	});

	it("goes back to resting when Claudio goes away in the middle of a dictation", async () => {
		const bridge = fakeBridgeFeed();
		followBridge(bridge.feed, deps.store);
		bridge.emit("connected", stateFixture("state-idle"));
		await appear(action, key, {});
		bridge.emit("state", stateFixture("state-dictation-listening"));
		await after(200);
		deps.hears(0.8);
		await after(200);
		expect(lastImage(key)).toContain('data-state="listening"');

		// The app quits, or its bridge is switched off: nobody will ever say this ended.
		bridge.emit("disconnected");
		await after(200);

		expect(lastImage(key)).toContain('data-state="rest"');
	});

	it("starts the dictation after that one on an empty meter", async () => {
		const bridge = fakeBridgeFeed();
		followBridge(bridge.feed, deps.store);
		bridge.emit("connected", stateFixture("state-idle"));
		await appear(action, key, {});
		bridge.emit("state", stateFixture("state-dictation-listening"));
		deps.hears(0.8);
		await after(200);
		bridge.emit("disconnected");
		await after(200);

		bridge.emit("connected", stateFixture("state-idle"));
		bridge.emit("state", stateFixture("state-dictation-listening"));
		await after(200);

		expect(lastImage(key)).toContain(micGlyph({ levels: [] }));
	});

	it("draws a key only when the drawing actually changed", async () => {
		deps.store.setConnected(true);
		await appear(action, key, {});
		const drawn = key.setImage.mock.calls.length;

		await says(null);
		await says(null, { label: "Prêt" });

		expect(key.setImage.mock.calls.length).toBe(drawn);
	});

	it("draws a key again from scratch after it left the page and came back", async () => {
		await appear(action, key, {});
		const drawn = key.setImage.mock.calls.length;

		action.onWillDisappear?.({ action: key } as never);
		await appear(action, key, {});

		expect(key.setImage.mock.calls.length).toBe(drawn + 1);
	});
});

describe("LevelMeter", () => {
	let redraw: ReturnType<typeof vi.fn<() => void>>;
	let meter: InstanceType<typeof LevelMeter>;

	beforeEach(() => {
		vi.useFakeTimers();
		redraw = vi.fn<() => void>();
		meter = new LevelMeter(redraw);
	});

	afterEach(() => {
		vi.useRealTimers();
	});

	it("starts on nothing heard", () => {
		expect(meter.levels).toEqual([]);
	});

	it("draws the first level at once, so the meter answers the voice", () => {
		meter.hear(0.4);

		expect(meter.levels).toEqual([0.4]);
		expect(redraw).toHaveBeenCalledOnce();
	});

	it("draws the ones that follow as one, when the window closes", () => {
		meter.hear(0.1);
		meter.hear(0.2);
		meter.hear(0.3);
		expect(redraw).toHaveBeenCalledOnce();

		vi.advanceTimersByTime(METER_WINDOW_MS);

		expect(redraw).toHaveBeenCalledTimes(2);
		expect(meter.levels).toEqual([0.1, 0.2, 0.3]);
	});

	it("stops redrawing once the voice stops", () => {
		meter.hear(0.1);
		meter.hear(0.2);
		vi.advanceTimersByTime(METER_WINDOW_MS);

		vi.advanceTimersByTime(METER_WINDOW_MS * 10);

		expect(redraw).toHaveBeenCalledTimes(2);
	});

	it("keeps the seven last levels, and forgets the rest", () => {
		for (const level of [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]) {
			meter.hear(level);
			vi.advanceTimersByTime(METER_WINDOW_MS);
		}

		expect(meter.levels).toEqual([0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]);
	});

	it("forgets what it heard, window and all", () => {
		meter.hear(0.1);
		meter.hear(0.2);

		meter.forget();
		vi.advanceTimersByTime(METER_WINDOW_MS * 4);

		expect(meter.levels).toEqual([]);
		expect(redraw, "the level held back belonged to a dictation that is over").toHaveBeenCalledOnce();
	});
});
