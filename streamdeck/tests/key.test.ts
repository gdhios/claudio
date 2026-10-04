import { describe, expect, it } from "vitest";

import { chevron, mascot, mic, micGlyph, musicNote, textCorrect, windowLayout, word } from "../src/render/glyphs.js";
import { bakeLabel, keySvg } from "../src/render/key.js";
import { GLYPH_CENTRE, theme } from "../src/render/theme.js";

describe("bakeLabel", () => {
	it("keeps a word that fits on one line at the largest size", () => {
		expect(bakeLabel("Corriger")).toEqual({ lines: ["Corriger"], fontSize: 11 });
	});

	it("keeps two short words on one line when they fit at the largest size", () => {
		expect(bakeLabel("Ton pro")).toEqual({ lines: ["Ton pro"], fontSize: 11 });
	});

	it("breaks a label only once it no longer fits on one line", () => {
		expect(bakeLabel("Traduire (FR)")).toEqual({ lines: ["Traduire", "(FR)"], fontSize: 11 });
	});

	it("prefers two lines at the largest size over one line made smaller", () => {
		const baked = bakeLabel("Action libre");

		expect(baked.lines).toEqual(["Action", "libre"]);
		expect(baked.fontSize).toBe(theme.label.maxFontSize);
	});

	it("breaks at the space that balances the two lines", () => {
		expect(bakeLabel("Un deux trois quatre").lines).toEqual(["Un deux", "trois quatre"]);
	});

	it("never makes more than two lines", () => {
		expect(bakeLabel("un deux trois quatre cinq six").lines).toHaveLength(2);
	});

	it("shrinks the font until the longest line fits", () => {
		const baked = bakeLabel("Professional tone");

		expect(baked.lines).toEqual(["Professional", "tone"]);
		expect(baked.fontSize).toBe(8);
		expect(12 * theme.label.widthPerCharacter * baked.fontSize).toBeLessThanOrEqual(theme.label.maxWidth);
	});

	it("shrinks a single long word that cannot be broken", () => {
		expect(bakeLabel("Lapacompris")).toEqual({ lines: ["Lapacompris"], fontSize: 9 });
	});

	it("stops shrinking at the smallest legible size", () => {
		expect(bakeLabel("Anticonstitutionnellement").fontSize).toBe(theme.label.minFontSize);
	});

	it("collapses the whitespace around and inside the label", () => {
		expect(bakeLabel("  Ton   pro \n").lines).toEqual(["Ton pro"]);
	});

	it("bakes an empty label into no lines at all", () => {
		expect(bakeLabel("   ").lines).toEqual([]);
	});
});

describe("keySvg", () => {
	it("draws a 72 unit key with the violet gradient and a corner radius of 9", () => {
		const svg = keySvg({ glyph: chevron(), label: "Prompt" });

		expect(svg).toContain('viewBox="0 0 72 72"');
		expect(svg).toContain('rx="9"');
		expect(svg).toContain('stop-color="#5E35A6"');
		expect(svg).toContain('stop-color="#3E106F"');
	});

	it("includes the glyph it was given", () => {
		expect(keySvg({ glyph: chevron(), label: "Prompt" })).toContain(chevron());
	});

	it("bakes each label line into the key", () => {
		const svg = keySvg({ glyph: chevron(), label: "Prompt expert" });

		expect(svg).toContain(">Prompt<");
		expect(svg).toContain(">expert<");
		expect(svg).toContain('font-size="11"');
	});

	it("draws no text when there is no label", () => {
		expect(keySvg({ glyph: chevron() })).not.toContain("<text");
	});

	it("escapes a label that would otherwise break the document", () => {
		const svg = keySvg({ glyph: chevron(), label: "A&<B>" });

		expect(svg).toContain("A&amp;&lt;B&gt;");
		expect(svg).not.toContain("<B>");
	});

	it("fades a dimmed key", () => {
		expect(keySvg({ glyph: chevron(), label: "Prompt", dimmed: true })).toContain('opacity="0.45"');
	});

	it("leaves a live key at full strength", () => {
		expect(keySvg({ glyph: chevron(), label: "Prompt" })).not.toContain('opacity="0.45"');
	});

	it("draws the dark background without the gradient", () => {
		const svg = keySvg({ glyph: windowLayout("leftHalf"), background: "dark" });

		expect(svg).toContain("#120E1C");
		expect(svg).not.toContain("#5E35A6");
	});

	it("names on the drawing what the key is showing", () => {
		expect(keySvg({ glyph: chevron(), state: "listening" })).toContain('data-state="listening"');
	});

	it("escapes a state that would otherwise break out of its attribute", () => {
		// Phases arrive over the wire, so a caller could hand one straight through.
		const svg = keySvg({ glyph: chevron(), state: 'x" onload="boom' });

		expect(svg).toContain("&quot;");
		expect(svg).not.toContain('onload="boom"');
	});

	it("names nothing when the key has no state to name", () => {
		expect(keySvg({ glyph: chevron(), label: "Prompt" })).not.toContain("data-state");
	});

	it("renders an Action key", () => {
		expect(keySvg({ glyph: textCorrect(), label: "Corriger" })).toMatchSnapshot();
	});

	it("renders a dimmed Action key", () => {
		expect(keySvg({ glyph: textCorrect(), label: "Corriger", dimmed: true })).toMatchSnapshot();
	});

	it("renders the What's playing? key", () => {
		expect(keySvg({ glyph: musicNote(), label: "J'écoute quoi ?" })).toMatchSnapshot();
	});
});

describe("glyphs", () => {
	it("draws a different window for every layout", () => {
		const layouts = ["leftHalf", "rightHalf", "topHalf", "bottomHalf", "maximize", "center", "nextScreen"] as const;
		const drawings = layouts.map((layout) => windowLayout(layout));

		expect(new Set(drawings).size).toBe(layouts.length);
	});

	it("paints the window in the dark family", () => {
		const svg = windowLayout("topLeft");

		expect(svg).toContain(theme.dark.frame);
		expect(svg).toContain(theme.dark.window);
	});

	it("draws a different mascot for every gaze", () => {
		const gazes = ["repos", "veille", "fait", "vide"] as const;

		expect(new Set(gazes.map((gaze) => mascot(gaze))).size).toBe(gazes.length);
	});

	it("centres the mascot on the glyph centre the theme sets", () => {
		const placement = /translate\((-?[\d.]+) (-?[\d.]+)\) scale\(([\d.]+)\)/.exec(mascot("repos"));
		expect(placement).not.toBeNull();
		const [, x, y, scale] = placement!.map(Number);

		// The master's "buste" occupies x 73→440 and y 75→342, so its centre is (256, 208.75).
		expect(x! + 256 * scale!).toBeCloseTo(GLYPH_CENTRE.x, 2);
		expect(y! + 208.75 * scale!).toBeCloseTo(GLYPH_CENTRE.y, 2);
	});

	it("builds the mascot from the shapes of the master drawing", () => {
		const svg = mascot("repos");

		// The moustache, the head ring and the antenna, quoted from icon/claudio_mascotte.svg.
		expect(svg).toContain("M256,239.765c-26.2,-26.2 -72.05,-22.925 -98.25,6.55");
		expect(svg).toContain("M364.5,182.25l0,102.5c0,28.286 -22.964,51.25 -51.25,51.25");
		expect(svg).toContain('cx="256" cy="96.745" r="21.255"');
	});

	it("escapes the word it draws", () => {
		expect(word("A&B")).toContain("A&amp;B");
	});
});

describe("micGlyph", () => {
	/** The bars of the level meter, left to right, as x and height. */
	function bars(svg: string): { x: number; height: number }[] {
		const group = /<g data-part="levels"[^>]*>(.*?)<\/g>/.exec(svg);
		expect(group, "the drawing carries no level meter").not.toBeNull();

		return [...group![1]!.matchAll(/<rect x="([\d.]+)" y="[\d.]+" width="[\d.]+" height="([\d.]+)"/g)].map(
			(match) => ({ x: Number(match[1]), height: Number(match[2]) }),
		);
	}

	it("draws the microphone alone when it is not listening", () => {
		expect(micGlyph()).toBe(mic());
	});

	it("keeps the same microphone while it listens, only smaller", () => {
		expect(micGlyph({ levels: [0.5] })).toContain(mic());
	});

	it("draws a full row of bars from the first frame on", () => {
		expect(bars(micGlyph({ levels: [] }))).toHaveLength(7);
		expect(bars(micGlyph({ levels: [0.2, 0.4] }))).toHaveLength(7);
	});

	it("lines the bars up from left to right", () => {
		const drawn = bars(micGlyph({ levels: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7] }));

		for (let index = 1; index < drawn.length; index++) {
			expect(drawn[index]!.x).toBeGreaterThan(drawn[index - 1]!.x);
		}
	});

	it("puts the newest level on the right", () => {
		const rising = bars(micGlyph({ levels: [0.1, 1] }));
		const falling = bars(micGlyph({ levels: [1, 0.1] }));

		expect(rising.at(-1)!.height).toBeGreaterThan(rising.at(-2)!.height);
		expect(falling.at(-1)!.height).toBeLessThan(falling.at(-2)!.height);
	});

	it("draws a louder level taller", () => {
		const quiet = bars(micGlyph({ levels: [0.1] })).at(-1)!.height;
		const loud = bars(micGlyph({ levels: [0.9] })).at(-1)!.height;

		expect(loud).toBeGreaterThan(quiet);
	});

	it("still draws a silent bar, so the row reads as listening", () => {
		expect(bars(micGlyph({ levels: [0] })).at(-1)!.height).toBeGreaterThan(0);
	});

	it("keeps every bar inside the key", () => {
		for (const bar of bars(micGlyph({ levels: [1, 1, 1, 1, 1, 1, 1] }))) {
			expect(bar.x).toBeGreaterThanOrEqual(8);
			expect(bar.x).toBeLessThanOrEqual(64);
		}
	});

	it("padlocks a hands-free dictation", () => {
		expect(micGlyph({ levels: [0.5], locked: true })).toContain('data-part="lock"');
	});

	it("draws no padlock while the key is held", () => {
		expect(micGlyph({ levels: [0.5] })).not.toContain('data-part="lock"');
	});
});
