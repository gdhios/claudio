# Claudio for Stream Deck

A Stream Deck plugin that drives Claudio: one key per action, one key held down to
dictate, one key per window layout. The keys draw themselves — glyph, violet and label
baked into an SVG — so the hardware shows what the app is doing rather than a title
typed over a picture. The Dictate key goes further and shows the voice itself: a meter
of the levels the app sends while it listens.

## How it talks to the app

Claudio opens a WebSocket on `127.0.0.1`, on an ephemeral port, and writes the port and
a one-shot token to a handshake file in its application support folder. The plugin reads
that file on every attempt — a port from the last run is worth nothing — introduces
itself with a `hello`, and from then on receives the app's state and the microphone
level.

The wire contract is `protocol/fixtures/`: one JSON file per frame shape, loaded by the
app's Swift tests and by this plugin's TypeScript tests at once. A field that changes
there breaks both sides in the same commit, on purpose. `protocol/README.md` says more.

## Layout

| Path                            | What it holds                                        |
| ------------------------------- | ---------------------------------------------------- |
| `src/bridge/`                   | The protocol as a value, and the connection that carries it |
| `src/render/`                   | Theme, glyphs, the key drawing, and what a dictation looks like |
| `src/state/`                    | What the keys draw from                              |
| `src/actions/`                  | The Action, Dictate and Window keys                  |
| `com.okonoma.claudio.sdPlugin/` | What Stream Deck loads: manifest, images, inspectors |
| `protocol/fixtures/`            | The wire contract                                    |

## Working on it

```sh
npm install
npm test     # vitest; touches no network, no Stream Deck, no real files
npm run lint # tsc --noEmit
npm run build
npx @elgato/cli validate com.okonoma.claudio.sdPlugin
```

`npm run build` bundles `src/plugin.ts` into `com.okonoma.claudio.sdPlugin/bin/plugin.js`.
`ws` is bundled in with it: the Node 20 runtime Stream Deck ships has no global
`WebSocket`.

## Strings

Every string a user reads is translated, French and English, in
`com.okonoma.claudio.sdPlugin/fr.json` and `en.json`. Their top level localizes the
manifest for Stream Deck; the `Localization` object under it is what
`streamDeck.i18n.translate` reads. The property inspectors run in a browser and cannot
reach those files, so `ui/locale.js` carries their own copy under the same key paths, and
`tests/locales.test.ts` fails the moment the two stop agreeing. The inspectors also carry
their own copy of sdpi-components under `ui/vendor/`, because a machine with no network
would otherwise show them empty.
Everything else — identifiers, comments, tests, commit messages — is English.

## Images

Key images and action icons are SVG. The marketplace icon has to be raster, so
`imgs/src/marketplace.svg` is its source; that file says which command renders it.
The mascot's shapes are quoted, without retouching, from `icon/claudio_mascotte.svg` at
the root of this repository.
