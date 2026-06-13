#!/usr/bin/env bash
#
# uninstall.sh — remove the app from /Applications and refresh Quick Look.
#
set -euo pipefail

DEST="/Applications/PkpassQuickLook.app"

if [[ -d "$DEST" ]]; then
  echo "🗑  Removing ${DEST}…"
  rm -rf "$DEST"
else
  echo "ℹ️  ${DEST} is not installed."
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -u "$DEST" >/dev/null 2>&1 || true

echo "♻️  Refreshing Quick Look…"
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

echo "✅ Uninstalled."
