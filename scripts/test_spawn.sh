#!/bin/bash
# test_spawn.sh — Clean Spawn Test for Switchboard Binary
# Strips AppImage-inherited environment poison and attempts a direct launch.
#
# Usage: bash scripts/test_spawn.sh [optional_url_arg]

set -euo pipefail

SWITCHBOARD_BIN="/home/jack/Documents/JBrowser/pir_switchboard/build/linux/x64/debug/bundle/pir_switchboard"

echo "=== JBrowser Clean Spawn Test ==="
echo "[test_spawn] Binary: ${SWITCHBOARD_BIN}"

# Check binary exists
if [ ! -f "$SWITCHBOARD_BIN" ]; then
    echo "[test_spawn] FATAL: Binary not found!"
    exit 1
fi

# Check executable
if [ ! -x "$SWITCHBOARD_BIN" ]; then
    echo "[test_spawn] Setting +x on binary..."
    chmod +x "$SWITCHBOARD_BIN"
fi

# Show current poison state
echo ""
echo "[test_spawn] --- Environment BEFORE sterilization ---"
echo "  LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-<unset>}"
echo "  APPDIR=${APPDIR:-<unset>}"
echo "  APPIMAGE=${APPIMAGE:-<unset>}"

# Sterilize
unset LD_LIBRARY_PATH 2>/dev/null || true
unset APPDIR 2>/dev/null || true
unset APPIMAGE 2>/dev/null || true
unset ARGV0 2>/dev/null || true
unset OWD 2>/dev/null || true

echo ""
echo "[test_spawn] --- Environment AFTER sterilization ---"
echo "  LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-<unset>}"
echo "  APPDIR=${APPDIR:-<unset>}"
echo "  APPIMAGE=${APPIMAGE:-<unset>}"

# ldd check
echo ""
echo "[test_spawn] --- Library dependency check (ldd) ---"
ldd "$SWITCHBOARD_BIN" 2>&1 | head -20

# Attempt launch
echo ""
URL_ARG="${1:-https://example.com/test.zip}"
echo "[test_spawn] Launching with arg: ${URL_ARG}"
echo "[test_spawn] ------- BEGIN STDOUT/STDERR -------"

"$SWITCHBOARD_BIN" "$URL_ARG" 2>&1

EXIT_CODE=$?
echo "[test_spawn] ------- END STDOUT/STDERR -------"
echo "[test_spawn] Exit code: ${EXIT_CODE}"

if [ $EXIT_CODE -eq 0 ]; then
    echo "[test_spawn] ✓ Binary launched and exited cleanly."
elif [ $EXIT_CODE -eq 139 ]; then
    echo "[test_spawn] ✗ SIGSEGV (Segmentation Fault) — likely missing .so or GLIBC mismatch."
elif [ $EXIT_CODE -eq 127 ]; then
    echo "[test_spawn] ✗ Binary not found or not executable."
else
    echo "[test_spawn] ✗ Non-zero exit code: ${EXIT_CODE}"
fi
