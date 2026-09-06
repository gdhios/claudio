#!/bin/bash
# Claudio's test protocol — three levels, from cheapest to most complete.
#
#   Scripts/test.sh             level 1: unit tests (dev loop, CI)
#   Scripts/test.sh --smoke     levels 1+2: + build + UI previews rendered offline
#   Scripts/test.sh --release   levels 1+2+3: + real API calls (--selftest)
#
# Level 1 — `swift test`: all the critical logic (SSE stream parsing, request
#   bodies, budgets, palette, cost counter, updates) with no network and no
#   permission. A few seconds.
# Level 2 — previews: the compiled app starts and renders each critical
#   screen to PNG (`--preview … --shot`), with no key and no global shortcut.
#   Catches what unit tests don't see: a screen that no longer builds.
# Level 3 — end to end: `--selftest` calls the real API (key required:
#   ANTHROPIC_API_KEY or Keychain) on the catalog path then the free path.
#   A few thousandths of a dollar; reserved for publishing.
#
# See TESTING.md for the full map: what's covered, where, why.
set -euo pipefail
cd "$(dirname "$0")/.."

LEVEL="${1:-}"
case "$LEVEL" in
    ""|--smoke|--release) ;;
    *) echo "usage : Scripts/test.sh [--smoke|--release]"; exit 1 ;;
esac

[ "$(uname)" = "Darwin" ] || { echo "❌ Claudio is a macOS app: this protocol runs on macOS."; exit 1; }

# ── Level 1: unit tests ────────────────────────────────────────────────
echo "── Level 1 · Unit tests (swift test) ──"
swift test
echo "✅ Unit tests green."
if [ -z "$LEVEL" ]; then exit 0; fi

# ── Level 2: the app starts and renders its screens ───────────────────────────────
echo ""
echo "── Level 2 · Offline UI previews ──"
swift build
BIN=".build/debug/Claudio"
SHOTS=".build/previews"
mkdir -p "$SHOTS"

# Renders a preview to PNG, bounded to 30s (alarm): a screen that no longer
# builds shows up as the exit code, a hang shows up at the watchdog.
preview_shot() {
    local mode="$1"
    local png="$SHOTS/$mode.png"
    local log="$SHOTS/$mode.log"
    rm -f "$png"
    local status=0
    perl -e 'alarm shift; exec @ARGV' 30 \
        "$BIN" --preview "$mode" --shot "$png" >"$log" 2>&1 || status=$?
    if [ "$status" -ne 0 ]; then
        echo "❌ Preview \"$mode\": exit code $status (142 = hung for 30s then killed)."
        cat "$log"
        exit 1
    fi
    # A tiny PNG is an empty render: the file should weigh in at its screen's size.
    local size
    size=$(stat -f%z "$png" 2>/dev/null || echo 0)
    if [ "$size" -lt 5000 ]; then
        echo "❌ Preview \"$mode\": $png missing or empty ($size bytes)."
        cat "$log"
        exit 1
    fi
    echo "   $mode: $size bytes"
}

# The screens everything passes through: panel (result, streaming, error,
# free instruction), palette (plain and filtered), Settings (API key, engine
# per action, local server, shortcuts).
for mode in panel panel-streaming panel-error panel-free palette palette-filtre settings settings-prompts settings-ollama settings-shortcuts; do
    preview_shot "$mode"
done
echo "✅ Critical screens build and render ($SHOTS/)."
if [ "$LEVEL" = "--smoke" ]; then exit 0; fi

# ── Level 3: the real API, on both request paths ──────────────────
echo ""
echo "── Level 3 · End to end against the API (--selftest) ──"
echo "→ Catalog path (correction)…"
"$BIN" --selftest "Bonjour, je voulait savoir si tu pouvait m'envoyer les document avant demain matin."
echo ""
echo "→ Free path (instruction typed at runtime)…"
"$BIN" --selftest "Le chat dort profondément." "Traduis en espagnol"
echo ""
echo "✅ Full protocol green: unit tests, previews, real API."
