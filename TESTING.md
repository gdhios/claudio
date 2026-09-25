# Testing

What Claudio must never break: the captured text leaves in a well-formed request, the stream comes back whole, the result replaces the selection, the clipboard survives, the cost is counted right, and updates arrive. Three levels, cheapest first. Each catches what the previous one cannot see, and each runs only as often as it earns.

## Levels

| Level | Command | Duration | When |
|---|---|---|---|
| 1 · Unit | `Scripts/test.sh` | seconds | every change; CI on every push and PR |
| 2 · UI smoke | `Scripts/test.sh --smoke` | ~2 min | CI on every push and PR, PNGs published as artifacts |
| 3 · End to end | `Scripts/test.sh --release` | +30 s, a few cents | at release time only |

- **Level 1**: all critical logic, no network, no permissions, no UI. The SSE stream is replayed from recorded transcripts, time is injected, UserDefaults are throwaway suites. Tests that compare displayed strings pin the app language rather than inherit the machine's.
- **Level 2**: the compiled app starts and renders every critical screen to PNG (`--preview <mode> --shot file.png`, no key, no network). A screen that no longer builds fails with an exit code or an empty PNG, the kind of breakage unit tests never see. Modes: `panel`, `panel-streaming`, `panel-long`, `panel-error`, `panel-noselection`, `panel-free`, `panel-free-filled`, `panel-free-noselection`, `panel-free-answer-track`, `palette`, `palette-filtre`, `palette-libre`, `palette-noselection`, `settings`, `settings-prompts`, `settings-ollama`, `settings-shortcuts`, `settings-about`; `--size small|normal|large|extraLarge` forces the panel text size.
- **Level 3**: `--selftest` calls the real API with the real key, on both request paths (catalog action, then free instruction). It is the only level that checks the live contract: auth, headers, accepted model IDs, production SSE, billed tokens. It fails through its exit code, so it blocks a release.

```bash
ANTHROPIC_API_KEY=sk-ant-… .build/release/Claudio --selftest "a text with some mistake"
ANTHROPIC_API_KEY=sk-ant-… .build/release/Claudio --selftest "Le chat dort." "Translate to Spanish"
```

- **Build directory**: level 1 goes through `Scripts/test.sh` rather than a bare `swift test`, because a working copy inside a synced folder cannot be built in place: a file provider reinstates Finder info on `.build` mid-build and `codesign` then refuses the test bundle ("resource fork, Finder information, or similar detritus not allowed"). The script builds outside the working copy and prints where; CI keeps `.build` and its cache. The rendered PNGs stay in `.build/previews` either way. `Scripts/build_app.sh` is unaffected: it clears the attributes on the assembled `.app` right before signing it.

## What protects each critical path

| Critical path | If it breaks | Net |
|---|---|---|
| Request building (system prompt, `<texte_source>` tag, token budget, model, temperature; with nothing selected, the request prompt and its `<consigne>` tag; the `<morceau_en_cours>` block, on the custom action only) | the model answers the selection instead of transforming it, a request is treated as a missing text, or the API returns 400 | `ClaudioRequestTests`, `FreeRequestTests`, `ClaudioCatalogTests`, `AnthropicClientTests` — level 1 |
| SSE parsing (text, billed tokens, truncation, in-stream errors) | incomplete text, wrong cost, silent error | `AnthropicClientTests` on transcripts — level 1; live at level 3 |
| Streaming display (fragment buffer) | text lost on screen, stuttering panel | `StreamBufferTests` — level 1 |
| Paste: never a partial or empty result | the selection is overwritten with half a result | `StreamBufferTests` (`canPaste`) — level 1 |
| Palette (filtering, ranks 1–9, free line always present; with nothing selected, only what works without a selection: What's playing?, then the free line) | an action becomes unreachable from the keyboard | `PaletteCatalogTests`, `PaletteDigitTests`, `PaletteWithoutSelectionTests`, `ClaudioCatalogTests` — level 1 |
| Correction cycle (shortcut to paste; with nothing selected, the catalog stops and the custom action asks for a request; retry sends again without capturing; the player read never holds the panel up, and the ♪ line names only a track that was sent) | a shortcut opens nothing, pastes the wrong text, or the custom action stops on “No selection found” | `CorrectionCoordinatorTests`, `SentTrackLineTests` — level 1 |
| Galette buttons (link encoding; which buttons a track gets, a browser's by the artist in its title; nothing without Galette; a click closes “What's playing?” and leaves the custom action up) | Galette refuses the link or opens the wrong artist, or an answer not pasted yet vanishes | `GaletteLinkTests`, `GaletteTrackLinksTests`, `ListeningCoordinatorTests`, `CorrectionCoordinatorTests` — level 1 |
| Cost counter (rates, totals, daily reset) | wrong figure displayed | `CostLedgerTests` — level 1 |
| Storage keys and IDs (raw values of actions, models, text sizes) | settings lost on update, API errors | `ClaudioCatalogTests`, `PanelTextSizeTests` — level 1 |
| Auto-update (version comparison, `version.json` format) | update offered in a loop, or never again | `UpdateCheckerTests` — level 1 |
| Screens build (panel, palette, Settings) | crash on opening a screen | level 2 |
| Live contract with the Anthropic API | all of the above, in production | level 3 |
| Dictation on a lone modifier key (a lone press told from a combination, left from right, guards) | ⌥( or ⌥⇧L opens a microphone and pauses the music, or right ⌥ never dictates | `LoneKeyGestureTests`, `LoneKeyRecordingTests`, `LoneModifierKeyTests` — level 1; the real keyboard in the checklist below |
| Selection capture, simulated paste, clipboard restore, global shortcuts | the core gesture | not automatable (Accessibility permission, real session): checklist below |

## Manual checklist before a release (2 minutes)

On the local build of the committed work (`Scripts/build_app.sh`):

1. Select text in a native app (Notes), ⌃⌥⌘I: the result pastes **over** the selection.
2. Same in Chrome or an Electron app: this is the simulated ⌘C path, not Accessibility.
3. Copy an **image**, run an action, paste the result: the image is back in the clipboard right after (multi-type restore).
4. ⌃⌥⌘K then a digit: that row runs; Esc leaves no trace.
5. Settings → About → "Check now" answers (up to date, or update offered).
6. Window snapping (Accessibility): with another app's window frontmost, ⌃⌥⌘ + arrows (halves), ↩ (maximize), and 7/9/1/3 (corners) / 5 (center) — from the top row **and** the numeric keypad. Toggling "Move windows from the keyboard" off in Settings → Shortcuts stops the snapping and frees all these keys.
7. Next display (needs two screens): snap a window to a half, then ⌃⌥⌘⇟ — it lands on the other screen **on the same half**, and pressing again cycles back. Same check with a maximized window.
8. Recent dictations (Accessibility): after a dictation, click into another text field and pick the top row of the menu bar's Recent dictations — the same text pastes **at the cursor**. With Claudio's Settings window in front, the same row copies the text instead of pasting it.
9. Music while dictating: with Spotify or Music playing, hold the dictation shortcut — playback pauses, and resumes once the key is released. Paused beforehand, it **stays paused** after the dictation. Same with a tapped dictation ended by the next press, and with Esc.
10. Dictation on a lone key (Accessibility): in Settings → Shortcuts → Dictate, click the field, press right ⌥ and let go — the field shows “Right ⌥” (“⌥ droite” in French). In Notes, hold right ⌥, speak, release: the text is pasted, and the combination set before (⌃A, say) no longer dictates. Type ⌥⇧L with right ⌥ (“|” on AZERTY): the character is typed, no panel opens, the music keeps playing. Left ⌥ alone does nothing. Tap right ⌥ once: it listens hands-free; press it again: the text is pasted.
11. What's playing? (the real player, which no test reads): with a track playing in Spotify or Music, ⌃⌥⌘S — the panel opens at once, shows the title, the artist and “album · player”, then Claude's notes stream in under them. Paused, the card says “paused” and the notes still come. ⌘C copies “Title — Artist” and closes the panel. With nothing playing: “Nothing playing”, and the panel closes itself. With a correction panel open, ⌃⌥⌘S replaces it; with the listening panel open, ⌃⌥⌘I replaces it.
12. The palette without a selection (Accessibility): click an empty spot so nothing is selected, ⌃⌥⌘K — the palette offers “What's playing?” then the custom action, ranked 1 and 2, with no quote of a selection. Enter or 1 closes it and opens the listening panel. Type “write a haiku about Mondays” then Enter: it goes out as a request and the answer streams in the same panel. ⌃⌥⌘I with nothing selected still says “No selection found” and closes itself. With a selection, 9 still launches the custom action, and “What's playing?” comes last, without a rank; type “musique” and it comes first, before the custom action, and Enter opens it.
13. The custom action with nothing selected (Accessibility, the real player): in Notes, put the cursor on an empty line, ⌃⌥⌘D — the field asks “What should Claudio do?” with no excerpt under it. With a track playing in Spotify or Music, type “write a message to share what I'm listening to”: the answer streams, names the track, and “♪ Title — Artist” shows under it. Enter pastes it at the cursor; ⌘C copies it instead. Hold ⌃⌥⌘D and say the request: same answer, and the track the dictation paused is still named. With nothing playing, no ♪ line. Over a selection, ⌃⌥⌘D still transforms it, with the ♪ line only when something plays; ⌃⌥⌘I never shows one.
14. Galette buttons (the real apps, which no test opens): with Galette installed and a track playing in Spotify or Music, ⌃⌥⌘S — Galette's icon, then “Artist” and “Album”, show under the card while the notes stream. “Album” opens Galette on the album, or on the artist when it doesn't have it, and the panel closes. Ask the custom action about the track: the same buttons end the ♪ line, and a click opens Galette while the panel stays, its answer still ready to paste. A YouTube video in a browser whose title reads “Artist – Title” gets “Artist” alone, for the left part; one titled otherwise gets no button. On a Mac without Galette, no button and no mention of it.

## Adding a feature means extending the net

- **New logic** (parsing, computation, filtering, state): a unit test in `Tests/ClaudioTests`, no network.
- **New screen or panel phase**: a `--preview` mode in `Support/PreviewMode.swift`, added to the list in `Scripts/test.sh`.
- **New field in the API contract or `version.json`**: lock it in `AnthropicClientTests` / `UpdateCheckerTests`.
- **New raw value** (action, model, setting): add it to the list fixed by `ClaudioCatalogTests`. It is a storage key and will not change.
- **Anything that needs Accessibility**: a line in the manual checklist.

Conventions: XCTest, test names state the behaviour, a header comment says what is at stake, not what the test does. Comments and test names are in English; user-facing strings are bilingual through `loc("…", en: "…")`, and the tests pin the app language to compare French labels.
