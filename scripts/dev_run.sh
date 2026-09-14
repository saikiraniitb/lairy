#!/bin/bash
# Fast local development build & run (No installation to /Applications required)

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "⚡️ Building Debug build..."
xcodegen
xcodebuild -scheme OpenClip -configuration Debug -destination 'platform=macOS,arch=arm64' build > /dev/null

# Ask Xcode where it just built, rather than globbing DerivedData: several OpenClip-*
# folders can exist (the hash changes with the project path) and picking the wrong one
# silently launches a stale binary.
BUILT_PRODUCTS_DIR="$(xcodebuild -scheme OpenClip -configuration Debug -destination 'platform=macOS,arch=arm64' -showBuildSettings 2>/dev/null | awk -F' = ' '/[[:space:]]BUILT_PRODUCTS_DIR = /{print $2; exit}')"
APP_PATH="$BUILT_PRODUCTS_DIR/OpenClip.app"

if [ ! -d "$APP_PATH" ]; then
  # Fall back to the most recently built bundle.
  APP_PATH="$(ls -dt "$HOME/Library/Developer/Xcode/DerivedData/OpenClip-"*/Build/Products/Debug/OpenClip.app 2>/dev/null | head -n 1)"
fi

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  echo "Error: Could not find built OpenClip.app in DerivedData"
  exit 1
fi

echo "Terminating old instances & launching from DerivedData..."
pkill -f OpenClip || true

# Intent Intelligence (Gemini) reads its API key from GEMINI_API_KEY in the process environment —
# never from a file, UserDefaults, or Keychain. This script never sets or hardcodes that value; it
# only needs to not clobber it. A plain `&` background job in this same shell already inherits
# every variable exported before this script ran, so `export GEMINI_API_KEY=...` in the calling
# shell before `./scripts/dev_run.sh` is sufficient — the explicit `env` below just makes that
# inheritance visible rather than relying on it implicitly.
if [ -z "${GEMINI_API_KEY:-}" ]; then
  echo "⚠️  GEMINI_API_KEY is not set in this shell — Intent Intelligence will report \"not configured\"."
  echo "    export GEMINI_API_KEY=... before running this script to enable it."
else
  echo "✓ GEMINI_API_KEY is set in this shell (value not shown)."
fi

env "$APP_PATH/Contents/MacOS/OpenClip" > /tmp/openclip.log 2>&1 &

echo "Running directly from: $APP_PATH (logs at /tmp/openclip.log)"
