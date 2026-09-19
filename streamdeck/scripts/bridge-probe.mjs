/*
 * Claudio's bridge, from a terminal — the way to see it work without a
 * Stream Deck on the desk.
 *
 *   node streamdeck/scripts/bridge-probe.mjs
 *
 * It reads the handshake file Claudio writes, connects, says hello, prints
 * every frame it receives on a line of its own, and sends what is typed:
 *
 *   action correct        a catalog action — also: free, palette
 *   dict down             hold the first dictation key (primary, cleanup)
 *   dict down secondary translateEN
 *   dict up               release it; `dict cancel` is Esc
 *   win topLeft           snap the frontmost window — also: nextScreen
 *   open                  open Claudio's Settings
 *
 * Ctrl-D closes the connection. No dependency: `WebSocket` is a global from
 * Node 22 on. On Node 20 (the runtime the plugin itself is given), run it
 * with `node --experimental-websocket`.
 */

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";

/** The protocol the frames speak. Not the handshake file's own `v`. */
const PROTOCOL_VERSION = 1;

const handshakePath = join(
  homedir(),
  "Library/Application Support/Claudio/streamdeck-bridge.json",
);

/** What a typed line becomes on the wire. */
const commands = {
  action: ([id = "correct"]) => ({ type: "action", id }),
  dict: ([event = "down", language = "primary", output = "cleanup"]) =>
    event === "down"
      ? { type: "dictation", event, language, output }
      : { type: "dictation", event },
  win: ([layout = "topLeft"]) => ({ type: "window", layout }),
  open: () => ({ type: "open", target: "settings" }),
};

function readHandshake() {
  try {
    return JSON.parse(readFileSync(handshakePath, "utf8"));
  } catch (error) {
    console.error(`No bridge to talk to: ${handshakePath} (${error.message})`);
    console.error("Claudio has to be running, with the bridge on in Settings.");
    process.exit(1);
  }
}

const { port, token } = readHandshake();
const socket = new WebSocket(`ws://127.0.0.1:${port}`);

/** Frames typed, or piped in, before the socket was up. */
const pending = [];

function send(frame) {
  if (socket.readyState !== WebSocket.OPEN) {
    pending.push(frame);
    return;
  }
  // The token never reaches the log: it drives Claudio until the next start.
  const shown = frame.type === "hello" ? { ...frame, token: "…" } : frame;
  console.log(`→ ${JSON.stringify(shown)}`);
  socket.send(JSON.stringify(frame));
}

socket.addEventListener("open", () => {
  send({ type: "hello", v: PROTOCOL_VERSION, token, plugin: "probe" });
  for (const frame of pending.splice(0)) send(frame);
});
socket.addEventListener("message", (event) => console.log(`← ${event.data}`));
socket.addEventListener("error", () => {
  console.error(`Nothing listening on 127.0.0.1:${port}.`);
  process.exit(1);
});
socket.addEventListener("close", () => {
  console.log("— closed");
  process.exit(0);
});

const lines = createInterface({ input: process.stdin });
lines.on("line", (line) => {
  const [name, ...rest] = line.trim().split(/\s+/);
  if (!name) return;
  const make = commands[name];
  if (!make) {
    console.error(`? ${name} — try: ${Object.keys(commands).join(", ")}`);
    return;
  }
  send(make(rest));
});
lines.on("close", () => {
  // Ctrl-D, or the end of a piped script: a moment for the last frames to
  // go out and for Claudio to answer them, then the socket closes — and the
  // probe leaves whether or not the close handshake comes back.
  setTimeout(() => socket.close(), 500);
  setTimeout(() => process.exit(0), 1500);
});
