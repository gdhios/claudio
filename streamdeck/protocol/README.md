# Bridge protocol fixtures

The wire contract between Claudio and its Stream Deck plugin, as JSON frames.
One file per message shape. The Swift tests (`Tests/ClaudioTests/Bridge/`) and the
plugin's TypeScript tests both load these files: a field that changes here breaks
both sides at once, on purpose.

Text frames over a WebSocket bound to 127.0.0.1. `v` is carried by `hello` and
`welcome` only; everything else is implied by that handshake.
