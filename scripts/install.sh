#!/usr/bin/env bash
#
# install.sh — build the app, copy it to /Applications, and refresh Quick Look.
# Safe to run repeatedly; it replaces any previous install.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

APP_PRODUCT="PkpassQuickLook.app"
DEST="/Applications/${APP_PRODUCT}"
CONFIG="${CONFIG:-Release}"
DERIVED="$ROOT/build"

echo "🛠  Building ${APP_PRODUCT} (${CONFIG})…"

# Regenerate the project from project.yml when xcodegen is available.
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate >/dev/null
fi

xcodebuild \
  -project PkpassQuickLook.xcodeproj \
  -scheme PkpassQuickLook \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  build >/dev/null

BUILT_APP="$DERIVED/Build/Products/${CONFIG}/${APP_PRODUCT}"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "❌ Build product not found at $BUILT_APP" >&2
  exit 1
fi

echo "📦 Installing to ${DEST}…"
rm -rf "$DEST"
cp -R "$BUILT_APP" "$DEST"

echo "🔗 Registering with Launch Services…"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true

echo "♻️  Refreshing Quick Look…"
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

# Nudge the extension host to pick up the new plug-ins.
pluginkit -a "$DEST/Contents/PlugIns/PkpassPreviewExtension.appex" >/dev/null 2>&1 || true
pluginkit -a "$DEST/Contents/PlugIns/PkpassThumbnailExtension.appex" >/dev/null 2>&1 || true

# Explicitly elect the extensions. On recent macOS a freshly-registered
# extension sits in a "default" state and won't be used until enabled.
pluginkit -e use -i com.ariomoniri.PkpassQuickLook.Preview >/dev/null 2>&1 || true
pluginkit -e use -i com.ariomoniri.PkpassQuickLook.Thumbnail >/dev/null 2>&1 || true

# Launching the host app once is how macOS elects third-party Quick Look extensions.
echo "🚀 Launching the host app once so macOS elects the extensions…"
open "$DEST" || true

echo ""
echo "✅ Installed. Registered Quick Look providers:"
pluginkit -m -p com.apple.quicklook.preview 2>/dev/null | grep -i pkpass || echo "   (preview provider will appear after first use)"
pluginkit -m -p com.apple.quicklook.thumbnail 2>/dev/null | grep -i pkpass || true

echo ""
echo "👉 Select a .pkpass file in Finder and press Space."
echo "   Try the bundled sample: examples/Skyline-BoardingPass.pkpass"
echo ""
echo "   If nothing appears: open PkpassQuickLook.app and click 'Refresh Quick Look',"
echo "   or enable it under System Settings ▸ General ▸ Login Items & Extensions ▸ Quick Look,"
echo "   then run:  qlmanage -r && qlmanage -r cache && killall Finder"
