#!/bin/bash
# diagnose_suite.sh — JBrowser Environmental Audit

BASE_DIR="/home/jack/Documents/JBrowser"
THORIUM="${BASE_DIR}/bin/Thorium_Browser_138.0.7204.303_AVX2.AppImage"
ARIA2C="${BASE_DIR}/bin/aria2c"
SWITCHBOARD_BIN="${BASE_DIR}/pir_switchboard/build/linux/x64/debug/bundle/pir_switchboard"
SOCKET_PATH="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/jbrowser/bridge.sock"

echo "--- JBrowser Diagnostic Audit ---"

# 1. Binary Checks
function check_bin() {
    if [ -f "$1" ]; then
        echo "[OK] Found: $1 ($(du -h "$1" | cut -f1))"
        if [ ! -x "$1" ]; then
            echo "[WARN] Not executable: $1. Fixing..."
            chmod +x "$1"
        fi
    else
        echo "[ERROR] Missing: $1"
    fi
}

check_bin "$THORIUM"
check_bin "$ARIA2C"
check_bin "$SWITCHBOARD_BIN"

# 2. Native Messaging Host Manifest
NATIVE_MANIFEST="${HOME}/.config/thorium/NativeMessagingHosts/com.pir.browser.engine.json"
if [ -L "$NATIVE_MANIFEST" ]; then
    echo "[OK] Native Host Symlink exists: $NATIVE_MANIFEST"
    echo "     Targets: $(readlink -f "$NATIVE_MANIFEST")"
elif [ -f "$NATIVE_MANIFEST" ]; then
    echo "[OK] Native Host Manifest is a regular file."
else
    echo "[ERROR] Native Host Manifest NOT found in system path."
fi

# 3. Extension IDs and Preferences
echo "[INFO] Expected Bridge ID: ajfepmgaamkbdfofhkhfklpabmfogmca"
echo "[INFO] Expected Switchboard ID: jbbghkkfkmcdpnbekmcpikclpfcbeeej"

# 4. Socket Check
if [ -S "$SOCKET_PATH" ]; then
    echo "[OK] UDS Socket active: $SOCKET_PATH"
else
    echo "[WARN] UDS Socket NOT found. Switchboard app is likely down."
fi

# 5. Process Check
echo "--- Process Table ---"
pgrep -fl "Thorium_Browser" || echo "Thorium is NOT running."
pgrep -fl "aria2c" || echo "aria2c is NOT running."
pgrep -fl "pir_switchboard" || echo "Switchboard is NOT running."

echo "--------------------------------"
