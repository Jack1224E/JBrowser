#!/usr/bin/python3
import json
import os

pref_path = os.path.expanduser("~/.config/thorium/Default/Preferences")
if not os.path.exists(pref_path):
    print(f"Error: Preferences file not found at {pref_path}")
    exit(1)

with open(pref_path, 'r') as f:
    prefs = json.load(f)

# Ensure extensions.settings exists
if 'extensions' not in prefs:
    prefs['extensions'] = {}
if 'settings' not in prefs['extensions']:
    prefs['extensions']['settings'] = {}

# Extension IDs
bridge_id = "jlclojmcifniclnahffcmhocbccljfgc"
switch_id = "mfkdafmmppeidkmpnfjminnjimjikigl"

# Inject pins
for ext_id in [bridge_id, switch_id]:
    if ext_id not in prefs['extensions']['settings']:
        prefs['extensions']['settings'][ext_id] = {}
    prefs['extensions']['settings'][ext_id]['toolbar_pin'] = "force_pinned"

# Save back
with open(pref_path, 'w') as f:
    json.dump(prefs, f, indent=2)

print(f"Successfully injected pins for {bridge_id} and {switch_id} into {pref_path}")
