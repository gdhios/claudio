#!/bin/bash
# Publie une version de Claudio de bout en bout.
#
#   Scripts/release.sh 1.4.0 "palette d'actions"
#
# Une version n'est pas « faite » quand elle compile : elle l'est quand elle est
# notarisée, poussée, publiée en release GitHub, déployée sur le site, annoncée
# par version.json et vérifiée en ligne. Ce script fait toute la chaîne, dans cet
# ordre, et s'arrête à la première étape qui échoue.
#
# Arguments :
#   $1  version X.Y.Z (obligatoire)
#   $2  titre court du commit et de la release (défaut : la version seule)
#
# Variables d'environnement :
#   NOTES     fichier de notes de version (défaut : dist/release_notes_X.Y.Z.md,
#             et à défaut les commits depuis le dernier tag)
#   SKIP_SITE 1 pour ne pas toucher au site (rare : correctif de code seul)
#
# Prérequis : `gh auth status` valide, profil notarytool `claudio-notary`,
# accès ssh `hostinger-vps-1072957`. Voir README pour leur mise en place.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
TITLE="${2:-}"
REMOTE="hostinger-vps-1072957"
REMOTE_DIR="/opt/apps/claudio/site"
SITE="https://claudio.okonoma.com"

if ! echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "usage : Scripts/release.sh X.Y.Z [\"titre court\"]"
    exit 1
fi
MINOR="${VERSION%.*}"          # 1.4.0 → 1.4, la version affichée sur la landing
ZIP="dist/Claudio-$VERSION.zip"
TAG="v$VERSION"
COMMIT_TITLE="$TAG${TITLE:+ : $TITLE}"

echo "══ Claudio $VERSION ══"

# ── 1. Le dépôt est-il en état de publier ? ────────────────────────────────────
echo "→ Vérifications préalables…"
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "❌ Pas sur main."; exit 1; }
git diff --quiet && git diff --cached --quiet || {
    echo "❌ Modifications non commitées : commit d'abord le travail, ce script ne publie"
    echo "   que le changement de version."
    exit 1
}
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "❌ Le tag $TAG existe déjà."; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "❌ gh non authentifié (gh auth login)."; exit 1; }
ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE" true || { echo "❌ VPS injoignable."; exit 1; }

# ── 2. Numéro de version, partout où il est écrit ──────────────────────────────
echo "→ Version $VERSION dans le script de build et sur les landings…"
sed -i '' "s/^VERSION=\".*\"/VERSION=\"$VERSION\"/" Scripts/build_app.sh
sed -i '' "s/⬇ Télécharger Claudio [0-9.]*/⬇ Télécharger Claudio $MINOR/" site/index.html
sed -i '' "s/⬇ Download Claudio [0-9.]*/⬇ Download Claudio $MINOR/" site/en/index.html
grep -q "^VERSION=\"$VERSION\"$" Scripts/build_app.sh || { echo "❌ Version non appliquée au build."; exit 1; }

# ── 3. Protocole de test complet, puis build notarisé ──────────────────────────
# Les trois niveaux de TESTING.md : unitaires, aperçus UI, API réelle.
Scripts/test.sh --release

echo "→ Build notarisé (le script remplace /Applications/Claudio.app : on quitte l'app)…"
osascript -e 'quit app "Claudio"' 2>/dev/null || true
NOTARIZE=1 Scripts/build_app.sh
[ -f "$ZIP" ] || { echo "❌ $ZIP absent : le build notarisé n'a rien produit."; exit 1; }

# ── 4. Commit de version, tag, push ────────────────────────────────────────────
echo "→ Commit et tag…"
git add Scripts/build_app.sh site/index.html site/en/index.html
git commit -m "$COMMIT_TITLE

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
git tag "$TAG"
git push origin main --tags

# ── 5. Release GitHub ──────────────────────────────────────────────────────────
NOTES_FILE="${NOTES:-dist/release_notes_$VERSION.md}"
echo "→ Release GitHub $TAG…"
if [ -f "$NOTES_FILE" ]; then
    gh release create "$TAG" "$ZIP" --title "Claudio $VERSION" --notes-file "$NOTES_FILE"
else
    gh release create "$TAG" "$ZIP" --title "Claudio $VERSION" --generate-notes
fi

# ── 6. Site : pages, binaire téléchargeable, flux de mise à jour ───────────────
if [ "${SKIP_SITE:-0}" != "1" ]; then
    echo "→ Déploiement du site…"
    # Pas de --delete : Claudio.zip et version.json vivent sur le serveur, pas dans git.
    rsync -az site/ "$REMOTE:$REMOTE_DIR/"
    scp -q "$ZIP" "$REMOTE:$REMOTE_DIR/Claudio.zip"
    # version.json est le flux que l'app interroge une fois par jour.
    ssh "$REMOTE" "printf '%s' '{\"version\":\"$VERSION\",\"url\":\"$SITE/Claudio.zip\"}' > $REMOTE_DIR/version.json"
fi

# ── 7. Vérification en ligne : ce qui est servi, pas ce qu'on a envoyé ─────────
echo "→ Vérification…"
FEED=$(curl -fsS "$SITE/version.json")
echo "   version.json : $FEED"
echo "$FEED" | grep -q "\"$VERSION\"" || { echo "❌ version.json ne sert pas $VERSION."; exit 1; }

LOCAL_SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
REMOTE_SHA=$(curl -fsS "$SITE/Claudio.zip" | shasum -a 256 | cut -d' ' -f1)
[ "$LOCAL_SHA" = "$REMOTE_SHA" ] || { echo "❌ Le zip servi diffère du zip notarisé."; exit 1; }
echo "   Claudio.zip : identique au zip notarisé ($LOCAL_SHA)"

for page in "/" "/en/" "/aide/" "/en/help/"; do
    curl -fsS -o /dev/null "$SITE$page" || { echo "❌ $SITE$page ne répond pas."; exit 1; }
done
curl -fsS "$SITE/" | grep -q "Télécharger Claudio $MINOR" || { echo "❌ Landing FR : version non à jour."; exit 1; }
curl -fsS "$SITE/en/" | grep -q "Download Claudio $MINOR" || { echo "❌ Landing EN : version non à jour."; exit 1; }
echo "   Landings FR et EN : en ligne, bouton en $MINOR"

gh release view "$TAG" --json assets --jq '.assets[].name' | grep -q "Claudio-$VERSION.zip" \
    || { echo "❌ La release GitHub n'a pas son zip."; exit 1; }
echo "   Release GitHub : zip présent"

echo "✅ Claudio $VERSION publiée : $SITE · https://github.com/gdhios/claudio/releases/tag/$TAG"
