#!/bin/bash
# Protocole de test de Claudio — trois niveaux, du moins cher au plus complet.
#
#   Scripts/test.sh             niveau 1 : tests unitaires (boucle de dev, CI)
#   Scripts/test.sh --smoke     niveaux 1+2 : + build + aperçus UI rendus hors réseau
#   Scripts/test.sh --release   niveaux 1+2+3 : + appels API réels (--selftest)
#
# Niveau 1 — `swift test` : toute la logique critique (parsing du flux SSE,
#   corps de requête, budgets, palette, compteur de dépense, mise à jour) sans
#   réseau ni permission. Quelques secondes.
# Niveau 2 — aperçus : l'app compilée démarre et rend chaque écran critique en
#   PNG (`--preview … --shot`), sans clé ni raccourci global. Attrape ce que
#   les tests unitaires ne voient pas : un écran qui ne se construit plus.
# Niveau 3 — bout en bout : `--selftest` appelle la vraie API (clé requise :
#   ANTHROPIC_API_KEY ou Trousseau) sur le chemin catalogue puis le chemin
#   libre. Quelques millièmes de dollar ; réservé à la publication.
#
# Voir TESTING.md pour la cartographie complète : quoi est couvert, où, pourquoi.
set -euo pipefail
cd "$(dirname "$0")/.."

LEVEL="${1:-}"
case "$LEVEL" in
    ""|--smoke|--release) ;;
    *) echo "usage : Scripts/test.sh [--smoke|--release]"; exit 1 ;;
esac

[ "$(uname)" = "Darwin" ] || { echo "❌ Claudio est une app macOS : ce protocole s'exécute sur macOS."; exit 1; }

# ── Niveau 1 : tests unitaires ────────────────────────────────────────────────
echo "── Niveau 1 · Tests unitaires (swift test) ──"
swift test
echo "✅ Tests unitaires verts."
if [ -z "$LEVEL" ]; then exit 0; fi

# ── Niveau 2 : l'app démarre et rend ses écrans ───────────────────────────────
echo ""
echo "── Niveau 2 · Aperçus UI hors réseau ──"
swift build
BIN=".build/debug/Claudio"
SHOTS=".build/previews"
mkdir -p "$SHOTS"

# Rend un aperçu en PNG, borné à 30 s (alarm) : un écran qui ne se construit
# plus se voit au code de sortie, un blocage au chien de garde.
preview_shot() {
    local mode="$1"
    local png="$SHOTS/$mode.png"
    local log="$SHOTS/$mode.log"
    rm -f "$png"
    local status=0
    perl -e 'alarm shift; exec @ARGV' 30 \
        "$BIN" --preview "$mode" --shot "$png" >"$log" 2>&1 || status=$?
    if [ "$status" -ne 0 ]; then
        echo "❌ Aperçu « $mode » : code de sortie $status (142 = bloqué 30 s puis tué)."
        cat "$log"
        exit 1
    fi
    # Un PNG minuscule est un rendu vide : le fichier doit peser son écran.
    local size
    size=$(stat -f%z "$png" 2>/dev/null || echo 0)
    if [ "$size" -lt 5000 ]; then
        echo "❌ Aperçu « $mode » : $png absent ou vide ($size octets)."
        cat "$log"
        exit 1
    fi
    echo "   $mode : $size octets"
}

# Les écrans par lesquels tout passe : panneau (résultat, flux, erreur,
# consigne libre), palette (nue et filtrée), Réglages (clé API, raccourcis).
for mode in panel panel-streaming panel-error panel-free palette palette-filtre settings settings-shortcuts; do
    preview_shot "$mode"
done
echo "✅ Les écrans critiques se construisent et se rendent ($SHOTS/)."
if [ "$LEVEL" = "--smoke" ]; then exit 0; fi

# ── Niveau 3 : la vraie API, sur les deux chemins de requête ──────────────────
echo ""
echo "── Niveau 3 · Bout en bout contre l'API (--selftest) ──"
echo "→ Chemin catalogue (correction)…"
"$BIN" --selftest "Bonjour, je voulait savoir si tu pouvait m'envoyer les document avant demain matin."
echo ""
echo "→ Chemin libre (consigne saisie à l'exécution)…"
"$BIN" --selftest "Le chat dort profondément." "Traduis en espagnol"
echo ""
echo "✅ Protocole complet vert : unitaires, aperçus, API réelle."
