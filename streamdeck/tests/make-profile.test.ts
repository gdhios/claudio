import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import JSZip from "jszip";
import { afterEach, describe, expect, it } from "vitest";

const { writeProfile } = await import("../scripts/make-profile.mjs");

/** One page's manifest, as written inside the profile's zip. */
type PageManifest = {
	Controllers: Array<{
		Type: string;
		Actions: Record<
			string,
			{
				Name: string;
				Settings: Record<string, unknown>;
				State: number;
				States: Array<{ Image: string; Title: string; ShowTitle: boolean }>;
				UUID: string;
			}
		>;
	}>;
};

/** The top-level manifest naming the profile's pages. */
type ProfileManifest = {
	Name: string;
	Version: string;
	Device: { Model: string; UUID: string };
	Pages: { Current: string; Default: string; Pages: string[] };
};

const dirs: string[] = [];

afterEach(async () => {
	await Promise.all(dirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })));
});

/**
 * Writes a profile into a fresh temporary file and unzips it into a fresh temporary
 * directory, the way a person double-clicking the file would.
 * @returns The directory holding the unzipped profile, and its top-level folder name.
 */
async function unzippedProfile(): Promise<{ dir: string; root: string }> {
	const workDir = await mkdtemp(join(tmpdir(), "claudio-profile-"));
	dirs.push(workDir);
	const destination = join(workDir, "Claudio.streamDeckProfile");
	await writeProfile(destination);

	const extractDir = join(workDir, "unzipped");
	const zip = await JSZip.loadAsync(await readFile(destination));
	const entries = Object.values(zip.files).filter((entry) => !entry.dir);
	await Promise.all(
		entries.map(async (entry) => {
			const { mkdir, writeFile } = await import("node:fs/promises");
			const target = join(extractDir, entry.name);
			await mkdir(join(target, ".."), { recursive: true });
			await writeFile(target, await entry.async("nodebuffer"));
		}),
	);

	const root = entries[0]!.name.split("/")[0]!;
	return { dir: extractDir, root };
}

/**
 * Reads and parses one of the profile's JSON manifests.
 * @param dir The directory returned by `unzippedProfile`.
 * @param path Its path inside the profile, e.g. "Profiles/<uuid>/manifest.json".
 * @returns The parsed manifest.
 */
async function manifest<T>(dir: string, path: string): Promise<T> {
	return JSON.parse(await readFile(join(dir, path), "utf8")) as T;
}

describe("make-profile", () => {
	it("names the profile Claudio and lists exactly three pages plus a distinct blank default", async () => {
		const { dir, root } = await unzippedProfile();

		const top = await manifest<ProfileManifest>(dir, `${root}/manifest.json`);

		expect(top.Name).toBe("Claudio");
		expect(top.Version).toBe("3.0");
		expect(top.Device).toEqual({ Model: "20GAA9901", UUID: "" });
		expect(top.Pages.Pages).toHaveLength(3);
		expect(top.Pages.Current).toBe(top.Pages.Pages[0]);
		expect(top.Pages.Pages).not.toContain(top.Pages.Default);
		expect(new Set(top.Pages.Pages).size).toBe(3);
	});

	it("draws the face across all fifteen tiles of the first page", async () => {
		const { dir, root } = await unzippedProfile();
		const top = await manifest<ProfileManifest>(dir, `${root}/manifest.json`);

		const face = await manifest<PageManifest>(dir, `${root}/Profiles/${top.Pages.Pages[0]}/manifest.json`);
		const tiles = face.Controllers[0]!.Actions;

		expect(Object.keys(tiles)).toHaveLength(15);
		for (const tile of Object.values(tiles)) {
			expect(tile.UUID).toBe("com.okonoma.claudio.face");
		}
	});

	it("puts a bare Return and a bare Escape on the actions page, reachable from the palette otherwise", async () => {
		const { dir, root } = await unzippedProfile();
		const top = await manifest<ProfileManifest>(dir, `${root}/manifest.json`);

		const actionsPage = await manifest<PageManifest>(dir, `${root}/Profiles/${top.Pages.Pages[1]}/manifest.json`);
		const tiles = actionsPage.Controllers[0]!.Actions;

		const hotkeys = Object.values(tiles).filter((tile) => tile.UUID === "com.elgato.streamdeck.system.hotkey");
		expect(hotkeys).toHaveLength(2);

		const codes = hotkeys
			.map((tile) => (tile.Settings.Hotkeys as Array<{ VKeyCode: number; NativeCode: number }>)[0]!)
			.map((key) => key.VKeyCode)
			.sort((a, b) => a - b);
		expect(codes).toEqual([36, 53]);

		for (const tile of hotkeys) {
			const [primary, unused] = tile.Settings.Hotkeys as Array<Record<string, unknown>>;
			expect(primary!.NativeCode).toBe(primary!.VKeyCode);
			expect(primary!.KeyCmd).toBe(false);
			expect(primary!.KeyCtrl).toBe(false);
			expect(primary!.KeyOption).toBe(false);
			expect(primary!.KeyShift).toBe(false);
			expect(unused!.VKeyCode).toBe(-1);
		}
	});

	it("keeps the eight other actions reachable, and still reaches the two moved by the palette key", async () => {
		const { dir, root } = await unzippedProfile();
		const top = await manifest<ProfileManifest>(dir, `${root}/manifest.json`);

		const actionsPage = await manifest<PageManifest>(dir, `${root}/Profiles/${top.Pages.Pages[1]}/manifest.json`);
		const tiles = actionsPage.Controllers[0]!.Actions;

		const ids = Object.values(tiles)
			.filter((tile) => tile.UUID === "com.okonoma.claudio.action")
			.map((tile) => tile.Settings.id);
		expect(ids.sort()).toEqual(
			["correct", "free", "makePrompt", "palette", "professionalTone", "summarize", "translateEN", "translateFR"].sort(),
		);
		expect(ids).not.toContain("expertPrompt");
		expect(ids).not.toContain("simplify");
		expect(ids).toContain("palette");
	});

	it("gives the actions page two dictate keys and the three navigation keys at their spelled-out coordinates", async () => {
		const { dir, root } = await unzippedProfile();
		const top = await manifest<ProfileManifest>(dir, `${root}/manifest.json`);

		const actionsPage = await manifest<PageManifest>(dir, `${root}/Profiles/${top.Pages.Pages[1]}/manifest.json`);
		const tiles = actionsPage.Controllers[0]!.Actions;

		const dictates = Object.values(tiles).filter((tile) => tile.UUID === "com.okonoma.claudio.dictate");
		expect(dictates.map((tile) => tile.Settings)).toEqual(
			expect.arrayContaining([
				{ language: "primary", output: "cleanup" },
				{ language: "primary", output: "translateEN" },
			]),
		);

		expect(tiles["2,2"]).toMatchObject({ UUID: "com.okonoma.claudio.navigate", Settings: { target: "face" } });
		expect(tiles["3,2"]).toMatchObject({ UUID: "com.okonoma.claudio.navigate", Settings: { target: "windows" } });
		expect(tiles["4,2"]).toMatchObject({ UUID: "com.okonoma.claudio.navigate", Settings: { target: "leave" } });
	});

	it("lays out the window page exactly as spelled out, with the two navigation keys back to the face and the actions", async () => {
		const { dir, root } = await unzippedProfile();
		const top = await manifest<ProfileManifest>(dir, `${root}/manifest.json`);

		const windowsPage = await manifest<PageManifest>(dir, `${root}/Profiles/${top.Pages.Pages[2]}/manifest.json`);
		const tiles = windowsPage.Controllers[0]!.Actions;

		const layoutAt = (coordinates: string) => tiles[coordinates]?.Settings.layout;
		expect(layoutAt("0,0")).toBe("topLeft");
		expect(layoutAt("1,0")).toBe("topHalf");
		expect(layoutAt("2,0")).toBe("topRight");
		expect(layoutAt("0,1")).toBe("leftHalf");
		expect(layoutAt("1,1")).toBe("center");
		expect(layoutAt("2,1")).toBe("rightHalf");
		expect(layoutAt("0,2")).toBe("bottomLeft");
		expect(layoutAt("1,2")).toBe("bottomHalf");
		expect(layoutAt("2,2")).toBe("bottomRight");
		expect(layoutAt("3,0")).toBe("maximize");
		expect(layoutAt("3,1")).toBe("nextScreen");

		expect(tiles["4,0"]).toMatchObject({ UUID: "com.okonoma.claudio.navigate", Settings: { target: "face" } });
		expect(tiles["4,2"]).toMatchObject({ UUID: "com.okonoma.claudio.navigate", Settings: { target: "actions" } });
	});

	it("gives every action a still image and no baked title, so the plugin draws its own key", async () => {
		const { dir, root } = await unzippedProfile();
		const top = await manifest<ProfileManifest>(dir, `${root}/manifest.json`);
		const face = await manifest<PageManifest>(dir, `${root}/Profiles/${top.Pages.Pages[0]}/manifest.json`);

		for (const tile of Object.values(face.Controllers[0]!.Actions)) {
			expect(tile.States).toEqual([{ Image: "", Title: "", ShowTitle: false }]);
			expect(tile.State).toBe(0);
		}
	});

	it("mints fresh UUIDs on every run", async () => {
		const first = await unzippedProfile();
		const firstTop = await manifest<ProfileManifest>(first.dir, `${first.root}/manifest.json`);

		const second = await unzippedProfile();
		const secondTop = await manifest<ProfileManifest>(second.dir, `${second.root}/manifest.json`);

		expect(first.root).not.toBe(second.root);
		expect(firstTop.Pages.Pages).not.toEqual(secondTop.Pages.Pages);
	});
});
