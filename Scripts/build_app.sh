#!/bin/bash
# Compile Plume en release et assemble Plume.app (par défaut dans /Applications).
#
# Variables d'environnement :
#   SIGN_IDENTITY  identité de signature (défaut : "Plume Local Dev")
#   DEST           dossier d'installation (défaut : /Applications)
#
# ⚠️ Sans certificat stable, la signature ad-hoc change à chaque build et macOS
# re-demande la permission Accessibilité + l'accès Trousseau après chaque rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Plume"
BUNDLE_ID="com.guillaumedhios.plume"
VERSION="1.0.0"
SIGN_IDENTITY="${SIGN_IDENTITY:-Plume Local Dev}"
DEST="${DEST:-/Applications}"
APP="$DEST/$APP_NAME.app"

echo "→ Compilation (release)…"
swift build -c release

echo "→ Assemblage de $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

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

echo "→ Signature…"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    codesign --force --sign "$SIGN_IDENTITY" "$APP"
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

touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" >/dev/null 2>&1 || true

echo "✅ $APP prêt. Lancer avec : open \"$APP\""
