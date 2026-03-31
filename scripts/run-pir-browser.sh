#!/bin/bash
# Pir Browser — Ultimate Launcher (v9.0.0)
# [LOCKED - DO NOT MODIFY FLAGS OR PATHS]

# 1. Start or Verify the Engine (aria2c RPC)
if ! pgrep -x "aria2c" > /dev/null; then
    echo "Starting aria2c engine..."
    chmod +x "/home/jack/Documents/JBrowser/bin/aria2c"
    "/home/jack/Documents/JBrowser/bin/aria2c" --enable-rpc --rpc-listen-all --rpc-allow-origin-all --daemon
else
    echo "aria2c engine is already running."
fi

# 2. Paths Configuration
BASE_DIR="/home/jack/Documents/JBrowser"
PROFILE_DIR="${BASE_DIR}/pir_profile"
DASHBOARD="file://${BASE_DIR}/UI/dashboard.html"
DASHBOARD="${DASHBOARD// /%20}"
THORIUM="${BASE_DIR}/bin/Thorium_Browser_138.0.7204.303_AVX2.AppImage"

# Ensure profile directory and Native Messaging Hosts exist
mkdir -p "${PROFILE_DIR}/NativeMessagingHosts"

BRIDGE_ID="jlclojmcifniclnahffcmhocbccljfgc"
SWITCH_ID="mfkdafmmppeidkmpnfjminnjimjikigl"

# 3. Generate the Native Messaging Host Manifest with BOTH IDs
cat <<EOF > "${PROFILE_DIR}/NativeMessagingHosts/com.pir.browser.engine.json"
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

# 4. Anti-Space Symlink Workaround for AppImage
# Chromium AppImage wrappers often corrupt comma-separated strings containing spaces.
# We create safe symlinks in /tmp to load the unpacked extensions flawlessly.
mkdir -p /tmp/pir_suite
ln -sfn "${BASE_DIR}/extensions/snatcher" "/tmp/pir_suite/bridge"
ln -sfn "${BASE_DIR}/extensions/switchboard" "/tmp/pir_suite/switchboard"

# 5. Pre-launch Profile Injection & Session Purge
# If the Preferences file exists, forcefully inject the pinned UI state.
# We also wipe the Sessions folder to prevent 'Not Found' tabs from previous crashes.
PREFS="${PROFILE_DIR}/Default/Preferences"
mkdir -p "$(dirname "${PREFS}")"

if [ ! -f "${PREFS}" ]; then
    # Seed the pristine profile to guarantee day-one extension pinning
    cat <<EOPREFS > "${PREFS}"
{
  "extensions": {
    "pinned_extensions": ["$BRIDGE_ID", "$SWITCH_ID"],
    "settings": {
      "$BRIDGE_ID": { "toolbar_pin": "force_pinned" },
      "$SWITCH_ID": { "toolbar_pin": "force_pinned" }
    }
  }
}
EOPREFS
else
    # Maintain pins on subsequent launches
    TEMP_PREFS=$(mktemp)
    if jq --arg bid "$BRIDGE_ID" --arg sid "$SWITCH_ID" '
      .extensions.pinned_extensions = (
        (.extensions.pinned_extensions // [])
        | if index($bid) then . else . + [$bid] end
        | if index($sid) then . else . + [$sid] end
      )
      | .extensions.settings[$bid].toolbar_pin = "force_pinned"
      | .extensions.settings[$sid].toolbar_pin = "force_pinned"
    ' "${PREFS}" > "${TEMP_PREFS}"; then
        mv "${TEMP_PREFS}" "${PREFS}"
    fi
fi

# 6. Session Hygiene & Dynamic Launch
# Kill lingering 'Not Found' tabs from previous failed space-splitting loads.
rm -rf "${PROFILE_DIR}/Default/Sessions" "${PROFILE_DIR}/Default/Last Session" "${PROFILE_DIR}/Default/Last Tabs"

cd "${BASE_DIR}" || exit 1
"${THORIUM}" \
  --user-data-dir="pir_profile" \
  --load-extension="/tmp/pir_suite/bridge,/tmp/pir_suite/switchboard" \
  --remote-debugging-port=9222 \
  --no-first-run \
  --no-default-browser-check \
  "${DASHBOARD}"
