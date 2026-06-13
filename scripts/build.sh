#!/usr/bin/env bash
#
# build.sh — regenerate the project, build everything, and run the tests.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

if command -v xcodegen >/dev/null 2>&1; then
  echo "⚙️  xcodegen generate"
  xcodegen generate >/dev/null
fi

echo "🧪 Running tests…"
xcodebuild test \
  -project PkpassQuickLook.xcodeproj \
  -scheme PkpassKit \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO

echo "🏗  Building app + extensions…"
xcodebuild build \
  -project PkpassQuickLook.xcodeproj \
  -scheme PkpassQuickLook \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" >/dev/null

echo "✅ Build + tests complete."
