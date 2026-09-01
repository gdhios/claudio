#!/bin/bash
# Compile Claudio en release et assemble Claudio.app (par défaut dans /Applications).
#
# Usage :
#   Scripts/build_app.sh              build local (certificat « Plume Local Dev »)
#   NOTARIZE=1 Scripts/build_app.sh   build partageable : Developer ID + hardened
#                                     runtime + notarisation Apple + zip dans dist/
#
# Variables d'environnement :
#   SIGN_IDENTITY    identité locale (défaut : "Plume Local Dev" — nom historique
#                    du certificat auto-signé dans le Trousseau ; indépendant du
#                    nom de l'app, le garder évite de recréer un certificat)
#   DEV_ID_IDENTITY  identité Developer ID (défaut : auto-détectée dans le Trousseau)
#   NOTARY_PROFILE   profil notarytool (défaut : "claudio-notary")
#   DEST             dossier d'installation (défaut : /Applications)
#
# Prérequis notarisation, une seule fois (compte Apple Developer requis) :
#   1. Certificat : Xcode → Settings… → Accounts → Manage Certificates… →
#      + → « Developer ID Application ».
#   2. Identifiants : mot de passe d'app sur https://account.apple.com, puis
#      xcrun notarytool store-credentials claudio-notary \
#        --apple-id <apple-id> --team-id <TEAMID> --password <mdp-app>
#      (le TEAMID est entre parenthèses dans le nom du certificat)
#
# ⚠️ Sans certificat stable, la signature ad-hoc change à chaque build et macOS
# re-demande la permission Accessibilité + l'accès Trousseau après chaque rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Claudio"
BUNDLE_ID="com.guillaumedhios.claudio"
VERSION="1.6.0"
SIGN_IDENTITY="${SIGN_IDENTITY:-Plume Local Dev}"
NOTARY_PROFILE="${NOTARY_PROFILE:-claudio-notary}"
DEST="${DEST:-/Applications}"
APP="$DEST/$APP_NAME.app"

echo "→ Résolution des dépendances…"
swift package resolve

# Correctif de dépendance, à réappliquer à chaque build (les checkouts SPM ne sont
# pas versionnés). L'accès aux ressources généré par SwiftPM cherche le bundle de
# KeyboardShortcuts à la racine du .app ; codesign refuse d'y sceller quoi que ce
# soit, donc le bundle vit dans Contents/Resources et l'accès échoue par un
# fatalError dès l'ouverture de l'onglet Raccourcis. Sur la machine de compilation
# le repli sur .build masque le crash : il ne se voyait que chez les utilisateurs.
KS_UTILS=".build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/Utilities.swift"
KS_FIX='Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("KeyboardShortcuts_KeyboardShortcuts.bundle")) } ?? .main'
if [ -f "$KS_UTILS" ]; then
    if grep -q 'bundle: \.module' "$KS_UTILS"; then
        echo "→ Correctif KeyboardShortcuts (chemin du bundle de ressources)…"
        sed -i '' "s|bundle: \\.module|bundle: $KS_FIX|" "$KS_UTILS"
    fi
    if ! grep -q "KeyboardShortcuts_KeyboardShortcuts.bundle" "$KS_UTILS"; then
        echo "❌ Correctif KeyboardShortcuts non appliqué : la dépendance a changé."
        echo "   Vérifier $KS_UTILS avant de publier, sinon l'onglet Raccourcis plantera."
        exit 1
    fi
else
    echo "❌ Dépendance KeyboardShortcuts introuvable dans .build/checkouts."
    exit 1
fi

echo "→ Compilation (release)…"
swift build -c release

echo "→ Assemblage de $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# Bundles de ressources SPM (Bundle.module de KeyboardShortcuts fatalError sans eux).
for bundle in .build/release/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>fr</string>
	<key>CFBundleExecutable</key><string>$APP_NAME</string>
	<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>$APP_NAME</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSHumanReadableCopyright</key><string>© Guillaume Dhios</string>
</dict>
</plist>
PLIST

# Icône optionnelle : placer un AppIcon.icns dans icon/ pour l'embarquer.
if [ -f "icon/AppIcon.icns" ]; then
    cp "icon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
fi

xattr -cr "$APP" 2>/dev/null || true

if [ "${NOTARIZE:-0}" = "1" ]; then
    echo "→ Signature Developer ID (hardened runtime)…"
    if [ -z "${DEV_ID_IDENTITY:-}" ]; then
        DEV_ID_IDENTITY=$(security find-identity -v -p codesigning \
            | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
    fi
    if [ -z "$DEV_ID_IDENTITY" ]; then
        echo "❌ Aucun certificat « Developer ID Application » dans le Trousseau."
        echo "   À créer une seule fois : Xcode → Settings… → Accounts →"
        echo "   Manage Certificates… → + → « Developer ID Application »."
        exit 1
    fi
    echo "   Identité : $DEV_ID_IDENTITY"
    codesign --force --sign "$DEV_ID_IDENTITY" --options runtime --timestamp "$APP"
    codesign --verify --strict "$APP"

    echo "→ Notarisation Apple (quelques minutes)…"
    mkdir -p dist
    UPLOAD_ZIP="dist/.upload.zip"
    rm -f "$UPLOAD_ZIP"
    ditto -c -k --keepParent "$APP" "$UPLOAD_ZIP"
    if ! SUBMIT_OUT=$(xcrun notarytool submit "$UPLOAD_ZIP" \
            --keychain-profile "$NOTARY_PROFILE" --wait 2>&1); then
        echo "$SUBMIT_OUT"
        echo "❌ Soumission impossible. Si le profil « $NOTARY_PROFILE » n'existe pas,"
        echo "   le créer une seule fois (mot de passe d'app sur account.apple.com) :"
        echo "   xcrun notarytool store-credentials $NOTARY_PROFILE \\"
        echo "     --apple-id <apple-id> --team-id <TEAMID> --password <mdp-app>"
        rm -f "$UPLOAD_ZIP"
        exit 1
    fi
    echo "$SUBMIT_OUT"
    rm -f "$UPLOAD_ZIP"
    if ! echo "$SUBMIT_OUT" | grep -q "status: Accepted"; then
        SUBMISSION_ID=$(echo "$SUBMIT_OUT" | sed -n 's/^ *id: //p' | head -1)
        echo "❌ Notarisation refusée. Détail du rapport :"
        echo "   xcrun notarytool log $SUBMISSION_ID --keychain-profile $NOTARY_PROFILE"
        exit 1
    fi

    echo "→ Agrafage du ticket…"
    xcrun stapler staple "$APP"

    SHARE_ZIP="dist/$APP_NAME-$VERSION.zip"
    rm -f "$SHARE_ZIP"
    ditto -c -k --keepParent "$APP" "$SHARE_ZIP"
    echo "✅ $SHARE_ZIP prêt à partager (dézipper dans /Applications, double-clic)."
else
    echo "→ Signature locale…"
    # Tentative directe : un certificat auto-signé fonctionne même marqué
    # CSSMERR_TP_NOT_TRUSTED (que `find-identity -v` ne listerait pas).
    if codesign --force --sign "$SIGN_IDENTITY" "$APP" 2>/dev/null; then
        echo "   Signé avec « $SIGN_IDENTITY »."
    else
        echo "⚠️  Certificat « $SIGN_IDENTITY » introuvable → signature ad-hoc."
        echo "    macOS re-demandera Accessibilité/Trousseau après chaque rebuild."
        echo "    Pour créer le certificat (une seule fois) : Trousseau d'accès →"
        echo "    Assistant de certification → Créer un certificat… →"
        echo "    nom « $SIGN_IDENTITY », type « Signature de code », racine auto-signée."
        codesign --force --sign - "$APP"
    fi
    codesign --verify --strict "$APP"
fi

touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" >/dev/null 2>&1 || true

echo "✅ $APP prêt. Lancer avec : open \"$APP\""
