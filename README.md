# Claudio

[![CI](https://github.com/gdhios/claudio/actions/workflows/ci.yml/badge.svg)](https://github.com/gdhios/claudio/actions/workflows/ci.yml)

macOS menu-bar app. Select text in any application, press a shortcut, and Claudio rewrites it through Claude (or a local Ollama model), streams the result in a floating panel, then pastes it back in place of the selection.

Bring your own API key. Nothing goes through a third-party server: the app talks to the Anthropic API (or your Ollama instance) directly.

**Download**: [claudio.okonoma.com](https://claudio.okonoma.com) or the [latest release](https://github.com/gdhios/claudio/releases/latest). Signed and notarized, macOS 14+, Apple Silicon. Unzip into /Applications.

## Usage

| Shortcut | Action |
|---|---|
| ⌃⌥⌘K | **Action palette**: type to filter, press 1–9 or ⏎ to run. Anything that matches nothing becomes a free instruction. |
| ⌃⌥⌘I | Fix spelling, grammar and phrasing, keeping language and tone |
| ⌃⌥⌘P | Turn a rough idea into a clear prompt |
| ⌃⌥⌘^ | Turn it into a full prompt (role, context, task, constraints, output format) |
| ⌃⌥⌘F | Translate to French |
| ⌃⌥⌘E | Translate to English |
| ⌃⌥⌘T | Rewrite in a professional tone |
| ⌃⌥⌘R | Summarize |
| ⌃⌥⌘L | Explain in plain words |
| ⌃⌥⌘D | Free instruction ("translate to Spanish", "make it bullet points"…) |

The panel opens near the pointer and streams the result. **⏎** pastes it over the selection and restores the clipboard; **Esc** cancels; **⌘C** copies only. The source app keeps focus throughout. Shortcuts and system prompts are editable in Settings.

Two things on first launch: an Anthropic API key (stored in the Keychain; `ANTHROPIC_API_KEY` overrides it in development) and the Accessibility permission, which macOS requests on the first shortcut.

## Build from source

```bash
Scripts/build_app.sh
open /Applications/Claudio.app
```

Swift Package Manager, Xcode 16+. The script builds in release, signs, and installs the bundle; signing and notarization options are documented in its header.

## How it works

- **Capture** ([Selection/](Sources/Claudio/Selection)): reads the selection through the Accessibility API, falls back to a simulated ⌘C for Chrome and Electron apps, and snapshots the clipboard to restore it after pasting, images and RTF included.
- **Actions** ([AI/ClaudioAction.swift](Sources/Claudio/AI/ClaudioAction.swift)): one enum case per action, carrying its system prompt and token budget. What is actually sent is a [ClaudioRequest](Sources/Claudio/AI/ClaudioRequest.swift), built from a catalog entry or a free instruction. The selected text travels inside a `<texte_source>` tag so that a selection like "summarize my emails" is transformed, not obeyed.
- **Providers** ([AI/AnthropicClient.swift](Sources/Claudio/AI/AnthropicClient.swift), [AI/OllamaClient.swift](Sources/Claudio/AI/OllamaClient.swift)): SSE streaming, shared `TextStreamClient` protocol. Parsing is separated from transport so it is tested on recorded transcripts. Model is chosen per action: Haiku 4.5 by default, Sonnet 5, Opus 5, or any local Ollama model.
- **Panel** ([UI/ResultPanelView.swift](Sources/Claudio/UI/ResultPanelView.swift)): a floating window that never steals focus. Stream fragments are batched every 60 ms; the window height follows the content.
- **Cost** ([Storage/CostLedger.swift](Sources/Claudio/Storage/CostLedger.swift)): billed tokens are read from the stream and totalled per day, locally. Roughly $0.12 per hundred short actions with Haiku.
- **Updates** ([Support/UpdateChecker.swift](Sources/Claudio/Support/UpdateChecker.swift)): a daily read of a `version.json`. No data is sent.

## Tests

```bash
swift test                  # unit tests, seconds
Scripts/test.sh --smoke     # + every screen rendered to PNG, no network
Scripts/test.sh --release   # + real API calls
```

CI runs the first two levels on every push and pull request and publishes the rendered screens as artifacts. [TESTING.md](TESTING.md) describes what each level protects.

## Known limits

- Simulated ⌘C/⌘V use physical key codes: fine on QWERTY and AZERTY, not on Dvorak or Bépo.
- "Launch at login" requires the packaged app in /Applications, not `swift run`.

## License

[MIT](LICENSE). Independent project, not affiliated with Anthropic. Claude is a trademark of Anthropic, PBC.
