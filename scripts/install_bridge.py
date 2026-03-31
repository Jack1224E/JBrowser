#!/usr/bin/env python3
"""
PIR Bridge Installer

Installs the native messaging host manifest for Thorium browser.
"""

import os
import json
import stat

# Configuration
THORIUM_CONFIG_PATH = os.path.expanduser("~/.config/thorium/NativeMessagingHosts/")
MANIFEST_NAME = "com.pir.browser.engine.json"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# Manifest content
manifest = {
    "name": "com.pir.browser.engine",
    "description": "PIR Browser Engine Bridge",
    "path": os.path.join(SCRIPT_DIR, "pir_host_launcher.sh"),
    "type": "stdio",
    "allowed_origins": [
        "chrome-extension://jlclojmcifniclnahffcmhocbccljfgc/"
    ]
}

def main():
    # Create config directory if needed
    os.makedirs(THORIUM_CONFIG_PATH, exist_ok=True)
    
    # Write manifest
    manifest_path = os.path.join(THORIUM_CONFIG_PATH, MANIFEST_NAME)
    with open(manifest_path, 'w') as f:
        json.dump(manifest, f, indent=2)
    print(f"✅ Manifest installed at {manifest_path}")
    
    # Set execute permissions
    scripts = [
        os.path.join(SCRIPT_DIR, "pir_host_launcher.sh"),
        os.path.join(SCRIPT_DIR, "pir_host.js")
    ]
    
    for script in scripts:
        if os.path.exists(script):
            st = os.stat(script)
            os.chmod(script, st.st_mode | stat.S_IEXEC)
            print(f"✅ Set execute permissions on {script}")
        else:
            print(f"⚠️  Script not found: {script}")

if __name__ == "__main__":
    main()