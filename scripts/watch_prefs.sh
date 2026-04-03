#!/bin/bash
# watch_prefs.sh — JBrowser Preferences Forensic Monitor
# Monitors the Thorium Preferences file for changes and reports
# which JSON keys are being modified when you pin/unpin extensions.
#
# Usage: bash scripts/watch_prefs.sh
# Then manually pin/unpin an extension in Thorium to trigger the diff.

set -euo pipefail

PREFS_FILE="/home/jack/Documents/JBrowser/pir_profile/Default/Preferences"
SNAPSHOT="/tmp/prefs_snapshot_before.json"

if [ ! -f "$PREFS_FILE" ]; then
    echo "[watch_prefs] ERROR: Preferences file not found at $PREFS_FILE"
    exit 1
fi

# Check for inotifywait
if ! command -v inotifywait &>/dev/null; then
    echo "[watch_prefs] ERROR: inotifywait not found."
    echo "  Install it with: sudo pacman -S inotify-tools"
    exit 1
fi

echo "[watch_prefs] === JBrowser Preference Watcher ==="
echo "[watch_prefs] Monitoring: $PREFS_FILE"
echo "[watch_prefs] Waiting for Thorium to write changes..."
echo "[watch_prefs] ACTION REQUIRED: Pin or unpin an extension in the browser NOW."
echo ""

# Take a baseline snapshot of critical keys
echo "[watch_prefs] Capturing baseline snapshot..."
jq '{
  "extensions.pinned_extensions": .extensions.pinned_extensions,
  "toolbar.pinned_actions": .toolbar.pinned_actions,
  "extensions.toolbar_pin_states": (
    [.extensions.settings | to_entries[] | select(.value.toolbar_pin != null) |
     {(.key): .value.toolbar_pin}] | add // {}
  )
}' "$PREFS_FILE" > "$SNAPSHOT" 2>/dev/null || echo "{}" > "$SNAPSHOT"

echo "[watch_prefs] Baseline captured:"
cat "$SNAPSHOT"
echo ""
echo "[watch_prefs] Now listening for file changes (Ctrl+C to stop)..."
echo "---"

# Loop: wait for modify events, then diff
while true; do
    # Wait for the file to be modified or moved-to (Chromium often writes a tmp and renames)
    inotifywait -qq -e modify -e moved_to -e close_write "$PREFS_FILE" 2>/dev/null || \
    inotifywait -qq -e modify -e close_write "$(dirname "$PREFS_FILE")" 2>/dev/null

    # Small delay to let Chromium finish writing
    sleep 0.5

    echo ""
    echo "[watch_prefs] === CHANGE DETECTED @ $(date -Iseconds) ==="

    # Capture the new state of the same keys
    AFTER=$(jq '{
      "extensions.pinned_extensions": .extensions.pinned_extensions,
      "toolbar.pinned_actions": .toolbar.pinned_actions,
      "extensions.toolbar_pin_states": (
        [.extensions.settings | to_entries[] | select(.value.toolbar_pin != null) |
         {(.key): .value.toolbar_pin}] | add // {}
      )
    }' "$PREFS_FILE" 2>/dev/null || echo "{}")

    echo "[watch_prefs] NEW STATE:"
    echo "$AFTER" | jq .

    echo ""
    echo "[watch_prefs] DIFF (before → after):"
    diff <(cat "$SNAPSHOT") <(echo "$AFTER") && echo "(no difference in tracked keys)" || true

    # Update the snapshot for the next round
    echo "$AFTER" > "$SNAPSHOT"

    echo "---"
    echo "[watch_prefs] Listening again..."
done
