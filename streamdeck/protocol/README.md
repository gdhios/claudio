# Bridge protocol fixtures

The wire contract between Claudio and its Stream Deck plugin, as JSON frames.
One file per message shape. The Swift tests (`Tests/ClaudioTests/Bridge/`) and the
plugin's TypeScript tests both load these files: a field that changes here breaks
both sides at once, on purpose.

An `action` frame carries the `id` of what the Action key launches. The catalog
entries go by the app's own raw values — `correct`, `makePrompt`, `expertPrompt`,
`translateFR`, `translateEN`, `professionalTone`, `summarize`, `simplify` — and three
ids are no catalog entry: `free` (the custom action), `palette`, and `whatsPlaying`,
which reads the player rather than the selection. Ids are added, never renamed; one
the app does not know is ignored, never guessed at.

Text frames over a WebSocket bound to 127.0.0.1. `v` is carried by `hello` and
`welcome` only; everything else is implied by that handshake.
