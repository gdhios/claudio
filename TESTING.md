# Testing

What Claudio must never break: the captured text leaves in a well-formed request, the stream comes back whole, the result replaces the selection, the clipboard survives, the cost is counted right, and updates arrive. Three levels, cheapest first. Each catches what the previous one cannot see, and each runs only as often as it earns.

## Levels

| Level | Command | Duration | When |
|---|---|---|---|
| 1 · Unit | `swift test` | seconds | every change; CI on every push and PR |
| 2 · UI smoke | `Scripts/test.sh --smoke` | ~2 min | CI on every push and PR, PNGs published as artifacts |
| 3 · End to end | `Scripts/test.sh --release` | +30 s, a few cents | at release time only |

- **Level 1**: all critical logic, no network, no permissions, no UI. The SSE stream is replayed from recorded transcripts, time is injected, UserDefaults are throwaway suites. Tests that compare displayed strings pin the app language rather than inherit the machine's.
- **Level 2**: the compiled app starts and renders every critical screen to PNG (`--preview <mode> --shot file.png`, no key, no network). A screen that no longer builds fails with an exit code or an empty PNG, the kind of breakage unit tests never see. Modes: `panel`, `panel-streaming`, `panel-long`, `panel-error`, `panel-noselection`, `panel-free`, `panel-free-filled`, `palette`, `palette-filtre`, `palette-libre`, `settings`, `settings-prompts`, `settings-ollama`, `settings-shortcuts`, `settings-about`; `--size small|normal|large|extraLarge` forces the panel text size.
- **Level 3**: `--selftest` calls the real API with the real key, on both request paths (catalog action, then free instruction). It is the only level that checks the live contract: auth, headers, accepted model IDs, production SSE, billed tokens. It fails through its exit code, so it blocks a release.

```bash
ANTHROPIC_API_KEY=sk-ant-… .build/release/Claudio --selftest "a text with some mistake"
ANTHROPIC_API_KEY=sk-ant-… .build/release/Claudio --selftest "Le chat dort." "Translate to Spanish"
```

## What protects each critical path

| Critical path | If it breaks | Net |
|---|---|---|
| Request building (system prompt, `<texte_source>` tag, token budget, model, temperature) | the model answers the selection instead of transforming it, or the API returns 400 | `ClaudioRequestTests`, `ClaudioCatalogTests`, `AnthropicClientTests` — level 1 |
| SSE parsing (text, billed tokens, truncation, in-stream errors) | incomplete text, wrong cost, silent error | `AnthropicClientTests` on transcripts — level 1; live at level 3 |
| Streaming display (fragment buffer) | text lost on screen, stuttering panel | `StreamBufferTests` — level 1 |
| Paste: never a partial or empty result | the selection is overwritten with half a result | `StreamBufferTests` (`canPaste`) — level 1 |
| Palette (filtering, ranks 1–9, free line always present) | an action becomes unreachable from the keyboard | `PaletteCatalogTests`, `PaletteDigitTests`, `ClaudioCatalogTests` — level 1 |
| Cost counter (rates, totals, daily reset) | wrong figure displayed | `CostLedgerTests` — level 1 |
| Storage keys and IDs (raw values of actions, models, text sizes) | settings lost on update, API errors | `ClaudioCatalogTests`, `PanelTextSizeTests` — level 1 |
| Auto-update (version comparison, `version.json` format) | update offered in a loop, or never again | `UpdateCheckerTests` — level 1 |
| Screens build (panel, palette, Settings) | crash on opening a screen | level 2 |
| Live contract with the Anthropic API | all of the above, in production | level 3 |
| Selection capture, simulated paste, clipboard restore, global shortcuts | the core gesture | not automatable (Accessibility permission, real session): checklist below |

## Manual checklist before a release (2 minutes)

On the local build of the committed work (`Scripts/build_app.sh`):

1. Select text in a native app (Notes), ⌃⌥⌘I: the result pastes **over** the selection.
2. Same in Chrome or an Electron app: this is the simulated ⌘C path, not Accessibility.
3. Copy an **image**, run an action, paste the result: the image is back in the clipboard right after (multi-type restore).
4. ⌃⌥⌘K then a digit: that row runs; Esc leaves no trace.
5. Settings → About → "Check now" answers (up to date, or update offered).

## Adding a feature means extending the net

- **New logic** (parsing, computation, filtering, state): a unit test in `Tests/ClaudioTests`, no network.
- **New screen or panel phase**: a `--preview` mode in `Support/PreviewMode.swift`, added to the list in `Scripts/test.sh`.
- **New field in the API contract or `version.json`**: lock it in `AnthropicClientTests` / `UpdateCheckerTests`.
- **New raw value** (action, model, setting): add it to the list fixed by `ClaudioCatalogTests`. It is a storage key and will not change.
- **Anything that needs Accessibility**: a line in the manual checklist.

Conventions: XCTest, test names state the behaviour, a header comment says what is at stake, not what the test does. The code base keeps French comments and strings; test names follow.
