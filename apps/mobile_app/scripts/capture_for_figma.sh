#!/usr/bin/env bash
# Boots the iPhone 17 simulator in light mode, runs the Figma capture
# integration test, copies the resulting PNGs to ~/Desktop/quest-figma/,
# and opens that folder so you can drag it into the Figma plugin.
set -euo pipefail

# ── Resolve paths ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$APP_DIR/.env.test"
OUT_DIR="$APP_DIR/build/figma_screenshots"
DESKTOP_DIR="$HOME/Desktop/quest-figma"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ Missing $ENV_FILE — needs TEST_EMAIL and TEST_PASSWORD" >&2
  exit 1
fi

# ── Find iPhone 17 (fallback: iPhone 15 Pro) ─────────────────────────────────
DEVICE_UDID="$(xcrun simctl list devices available \
  | grep -E "iPhone 17 \(" \
  | head -1 \
  | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/' || true)"

if [[ -z "$DEVICE_UDID" ]]; then
  echo "ℹ️  iPhone 17 not found — falling back to iPhone 15 Pro"
  DEVICE_UDID="$(xcrun simctl list devices available \
    | grep -E "iPhone 15 Pro \(" \
    | head -1 \
    | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/' || true)"
fi

if [[ -z "$DEVICE_UDID" ]]; then
  echo "❌ No suitable iPhone simulator installed" >&2
  exit 1
fi

echo "📱 Using simulator $DEVICE_UDID"

# ── Boot + force light appearance ────────────────────────────────────────────
xcrun simctl boot "$DEVICE_UDID" 2>/dev/null || true
open -a Simulator
xcrun simctl bootstatus "$DEVICE_UDID" -b
xcrun simctl ui "$DEVICE_UDID" appearance light

# ── Clean previous run ───────────────────────────────────────────────────────
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# ── Run flutter drive ────────────────────────────────────────────────────────
cd "$APP_DIR"

export FIGMA_CAPTURE_DIR="$OUT_DIR"

flutter drive \
  --debug \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/figma_capture_test.dart \
  -d "$DEVICE_UDID" \
  --dart-define-from-file="$ENV_FILE" \
  --dart-define=SUPABASE_URL=https://api.bsheel.app \
  "--dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg0MDIzMjcyLCJleHAiOjIwOTkzODMyNzJ9.0HGp8OvHc0peJcxlditiKrzFpz442iITeFQhyA_Vu7s" \
  --dart-define=MIXPANEL_TOKEN=55b3f6acdaa760fc8a637a591692ce5c

# ── Copy to Desktop folder for easy Figma plugin pickup ──────────────────────
mkdir -p "$DESKTOP_DIR"
rm -f "$DESKTOP_DIR"/*.png 2>/dev/null || true
cp "$OUT_DIR"/*.png "$DESKTOP_DIR"/

echo
echo "✅ Captured $(ls "$DESKTOP_DIR"/*.png 2>/dev/null | wc -l | tr -d ' ') screenshots"
echo "📂 $DESKTOP_DIR"
open "$DESKTOP_DIR"
