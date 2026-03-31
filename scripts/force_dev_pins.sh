#!/bin/bash
# Phase D Step 2 (Updated for V6.4.1): Force-pin extensions into current Thorium profile.
PREFS="$HOME/.config/thorium/Default/Preferences"
BRIDGE_ID="jlclojmcifniclnahffcmhocbccljfgc"
SWITCH_ID="mfkdafmmppeidkmpnfjminnjimjikigl"

if [ ! -f "$PREFS" ]; then
    echo "ERROR: Preferences file not found at $PREFS"
    exit 1
fi

cp "$PREFS" "${PREFS}.bak.$(date +%s)"
echo "Backup created."

TEMP=$(mktemp)
jq --arg bid "$BRIDGE_ID" --arg sid "$SWITCH_ID" '
  .extensions.pinned_extensions = (
    (.extensions.pinned_extensions // [])
    | if index($bid) then . else . + [$bid] end
    | if index($sid) then . else . + [$sid] end
  )
  | .extensions.settings[$bid].toolbar_pin = "force_pinned"
  | .extensions.settings[$sid].toolbar_pin = "force_pinned"
' "$PREFS" > "$TEMP"

if [ $? -eq 0 ]; then
    mv "$TEMP" "$PREFS"
    echo "Successfully injected pins for $BRIDGE_ID and $SWITCH_ID."
else
    echo "ERROR: jq failed. Preferences NOT modified."
    rm -f "$TEMP"
    exit 1
fi
