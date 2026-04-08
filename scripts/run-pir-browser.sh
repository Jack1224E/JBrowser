#!/bin/bash
# Pir Browser — Ghost Launcher (v11.0.0 — Synchronized)
# [PERSISTENT PROFILE - Dual-Key Pinning Active]

# 2. Workspace & Persistent Profile Initialization
BASE_DIR="/home/jack/Documents/JBrowser"
THORIUM="${BASE_DIR}/bin/Thorium_Browser_138.0.7204.303_AVX2.AppImage"
DASHBOARD="file://${BASE_DIR}/UI/dashboard.html"
DASHBOARD="${DASHBOARD// /%20}"

# Create a persistent profile directory (No longer in RAM)
PROFILE_DIR="${HOME}/.config/jbrowser_profile"
SYSTEM_HOSTS_DIR="${HOME}/.config/thorium/NativeMessagingHosts"
mkdir -p "${SYSTEM_HOSTS_DIR}"

if [ ! -d "$PROFILE_DIR" ]; then
    echo "[Launcher] New profile detected. Performing initial seeding..."
    mkdir -p "${PROFILE_DIR}/Default"
    cp "${BASE_DIR}/manifests/initial_preferences" "${PROFILE_DIR}/initial_preferences"
    cp "${BASE_DIR}/manifests/initial_preferences" "${PROFILE_DIR}/master_preferences"
    cp "${BASE_DIR}/manifests/initial_preferences" "${PROFILE_DIR}/Default/Preferences"
else
    echo "[Launcher] Existing profile found. Skipping destructive seeding."
fi

# 2b. Environment Unification — Remove orphaned profile to prevent confusion
ORPHAN_PROFILE="${BASE_DIR}/pir_profile"
if [ -d "$ORPHAN_PROFILE" ]; then
    echo "[Launcher] Cleaning up orphaned profile at ${ORPHAN_PROFILE}..."
    rm -rf "$ORPHAN_PROFILE"
    echo "[Launcher] Orphan profile removed."
fi

# 3. The Vanish (Automatic Cleanup Trap)
# We ONLY clean up the native messaging symlink, but we PRESERVE the profile data.
trap 'rm -f "${SYSTEM_HOSTS_DIR}/com.pir.browser.engine.json"' EXIT

# 4. Surgical Extension Pinning (Dual-Key JQ Patching)
# Golden IDs — verified from live browser session (path-derived, stable)
BRIDGE_ID="jlclojmcifniclnahffcmhocbccljfgc"
SWITCH_ID="mfkdafmmppeidkmpnfjminnjimjikigl"
PREFS_FILE="${PROFILE_DIR}/Default/Preferences"

if [ -f "$PREFS_FILE" ]; then
    echo "[Launcher] Surgically patching extension pins in $PREFS_FILE..."
    echo "[Launcher] Golden IDs: Bridge=${BRIDGE_ID}, Switchboard=${SWITCH_ID}"

    # Dual-Key Patch:
    #   Key A: .extensions.pinned_extensions — the list of pinned IDs
    #   Key B: .extensions.settings[ID].toolbar_pin — the per-extension visibility toggle
    # Graceful handling: initialize pinned_extensions to [] if null
    jq --arg b "$BRIDGE_ID" --arg s "$SWITCH_ID" '
      .extensions.pinned_extensions = ((.extensions.pinned_extensions // []) + [$b, $s] | unique) |
      .extensions.settings[$b].toolbar_pin = "force_pinned" |
      .extensions.settings[$s].toolbar_pin = "force_pinned"
    ' "$PREFS_FILE" > "${PREFS_FILE}.tmp" && mv "${PREFS_FILE}.tmp" "$PREFS_FILE"

    if [ $? -eq 0 ]; then
        echo "[Launcher] ✓ Dual-key patch applied successfully."
        # Verification: confirm the keys are present
        PINNED=$(jq -r '.extensions.pinned_extensions | join(", ")' "$PREFS_FILE" 2>/dev/null)
        BRIDGE_PIN=$(jq -r --arg b "$BRIDGE_ID" '.extensions.settings[$b].toolbar_pin // "MISSING"' "$PREFS_FILE" 2>/dev/null)
        SWITCH_PIN=$(jq -r --arg s "$SWITCH_ID" '.extensions.settings[$s].toolbar_pin // "MISSING"' "$PREFS_FILE" 2>/dev/null)
        echo "[Launcher] ✓ Pinned list: [${PINNED}]"
        echo "[Launcher] ✓ Bridge toolbar_pin: ${BRIDGE_PIN}"
        echo "[Launcher] ✓ Switchboard toolbar_pin: ${SWITCH_PIN}"
    else
        echo "[Launcher] ✗ Error: Dual-key JQ patching failed!"
    fi
else
    echo "[Launcher] Warning: Preferences file not yet generated. Pins will apply on next boot."
fi

# 5. Dedicated Native Messaging Host (Secure Deployment)
# We restrict the manifest ONLY to Thorium and our ephemeral Ghost Mode profile.
# This prevents other installed browsers (Chrome, Brave) from 'seeing' the vault host.
RAM_MANIFEST="${PROFILE_DIR}/com.pir.browser.engine.json"
cat <<EOF > "$RAM_MANIFEST"
{
  "name": "com.pir.browser.engine",
  "description": "Pir Engine Host",
  "path": "${BASE_DIR}/scripts/pir_host_launcher.sh",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://${BRIDGE_ID}/",
    "chrome-extension://${SWITCH_ID}/"
  ]
}
EOF

# Narrow-scope deployment
NMH_DIRS=(
    "${HOME}/.config/thorium/NativeMessagingHosts"
    "${PROFILE_DIR}/NativeMessagingHosts"
)

for dir in "${NMH_DIRS[@]}"; do
    mkdir -p "$dir"
    ln -sfn "$RAM_MANIFEST" "$dir/com.pir.browser.engine.json"
done
echo "[Launcher] ✓ Native Messaging manifest deployed to ${#NMH_DIRS[@]} locations."

# 6. Anti-Space Symlink Workaround for AppImage Extensions
mkdir -p /tmp/pir_suite
ln -sfn "${BASE_DIR}/extensions/snatcher" "/tmp/pir_suite/bridge"
ln -sfn "${BASE_DIR}/extensions/switchboard" "/tmp/pir_suite/switchboard"

# 7. Ghost Launch
cd "${BASE_DIR}" || exit 1
echo "[Launcher] Launching Pir Browser (Ghost Mode)..."
echo "[Launcher] Profile: ${PROFILE_DIR}"

"${THORIUM}" \
  --user-data-dir="${PROFILE_DIR}" \
  --load-extension="/tmp/pir_suite/bridge,/tmp/pir_suite/switchboard" \
  --remote-debugging-port=9222 \
  --no-first-run \
  --no-default-browser-check \
  --homepage="${DASHBOARD}" \
  "${DASHBOARD}" &

# 8. Polling Loop — Keep the script alive while Thorium is running.
# This prevents the EXIT trap from firing prematurely when the AppImage
# forks and returns control to the shell.
THORIUM_PID=$!
echo "[Launcher] Thorium PID: ${THORIUM_PID}"
sleep 2  # Give the AppImage time to mount and fork

while pgrep -f "Thorium_Browser" > /dev/null; do
    sleep 1
done

echo "[Launcher] Thorium has exited. Cleaning up..."
