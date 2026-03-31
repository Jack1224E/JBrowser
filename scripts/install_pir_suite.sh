#!/bin/bash

# Pir Browser — Silent Sidecar Deployment Installer (V6.4)
# This script configures Thorium to auto-load and auto-pin extensions without managed locking.

PROJECT_ROOT="/home/jack/Documents/Pir Browser"
EXT_DIR="$HOME/.config/thorium/External Extensions"
THORIUM_BIN_DIR="$PROJECT_ROOT/_legacy/binaries/squashfs-root/usr/bin"

BRIDGE_ID="jlclojmcifniclnahffcmhocbccljfgc"
SWITCH_ID="mfkdafmmppeidkmpnfjminnjimjikigl"

echo "Deploying Pir Browser Sidecar Suite..."

# 1. Create External Extensions Directory
mkdir -p "$EXT_DIR"

# 2. Write Extension Pointers
echo "Writing extension pointers to $EXT_DIR..."

cat <<EOF > "$EXT_DIR/$BRIDGE_ID.json"
{
  "external_directory": "$PROJECT_ROOT/core_bridge/extension",
  "managed_storage": false
}
EOF

cat <<EOF > "$EXT_DIR/$SWITCH_ID.json"
{
  "external_directory": "$PROJECT_ROOT/core_bridge/switchboard",
  "managed_storage": false
}
EOF

# 3. Deploy initial_preferences
echo "Deploying initial_preferences to $THORIUM_BIN_DIR..."
mkdir -p "$THORIUM_BIN_DIR"
cat <<EOF > "$THORIUM_BIN_DIR/initial_preferences"
{
  "extensions": {
    "settings": {
      "$BRIDGE_ID": { "toolbar_pin": "force_pinned" },
      "$SWITCH_ID": { "toolbar_pin": "force_pinned" }
    }
  }
}
EOF

echo "Sidecar Deployment Complete!"
echo "Launch your browser without --load-extension to verify."
