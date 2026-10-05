#!/usr/bin/env python3
"""Claude Code hook relay for Claudio.

Claude Code runs this hook on Stop, Notification, UserPromptSubmit and
SessionEnd, with the event as JSON on stdin. The relay decides nothing: it
hands that JSON, untouched, to Claudio, which applies the rules and drives
the Ulanzi clock. Claudio publishes where it listens in a handshake file,
with a port and a token that change at every launch.

When Claudio isn't running (no handshake file, connection refused), or
anything else goes wrong, the relay exits 0 without a word: a hook must
never get in a session's way. Python 3 standard library only.
"""
import json
import os
import sys
import urllib.request

HANDSHAKE = os.path.join(os.path.expanduser("~"), "Library", "Application Support",
                         "Claudio", "claude-code-hub.json")
TIMEOUT = 1.5  # seconds: Claudio answers at once, before doing anything


def read_event():
    """The hook's JSON as it came, or None when stdin holds no JSON object."""
    raw = sys.stdin.buffer.read()
    try:
        if not isinstance(json.loads(raw), dict):
            return None
    except ValueError:
        return None
    return raw


def read_handshake():
    """Claudio's port and token, or None when Claudio isn't listening."""
    try:
        with open(HANDSHAKE, "rb") as f:
            handshake = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(handshake, dict):
        return None
    port, token = handshake.get("port"), handshake.get("token")
    if isinstance(port, bool) or not isinstance(port, int) or not 0 < port < 65536:
        return None
    if not isinstance(token, str) or not token.isalnum():
        return None
    return port, token


def post(raw, port, token):
    request = urllib.request.Request(
        "http://127.0.0.1:%d/claude-code/%s" % (port, token), data=raw, method="POST",
        headers={"Content-Type": "application/json"})
    # No proxy: Claudio is on this Mac, and the token is no proxy's business.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(request, timeout=TIMEOUT) as response:
        response.read()


def main():
    raw = read_event()
    if raw is None:
        return
    handshake = read_handshake()
    if handshake is None:
        return
    post(raw, *handshake)


if __name__ == "__main__":
    try:
        main()
    except BaseException:  # whatever happened, the session goes on
        pass
    sys.exit(0)
