#!/bin/bash

# Pir Browser Complete Environment Cleanup Script
# This script removes all extensions, native messaging hosts, and managed policies.

echo "Starting Pir Browser environment cleanup..."

# List of files to remove (System-level, requires sudo)
SYSTEM_FILES=(
    "/etc/thorium/policies/managed/pir_browser_lock.json"
    "/etc/chromium/policies/managed/pir_browser_policies.json"
    "/usr/share/thorium/extensions/cpblfjnekigpmeeeddljkohopamoldjp.json"
    "/usr/share/thorium/extensions/dnpahafmecohlldddcjkhbhagjkmibjk.json"
    "/usr/share/thorium/extensions/ghnomclnhmdfclndfmcfjmkpbcidkndf.json"
    "/usr/share/thorium/extensions/ginhlpeefamljockmggdgooajnjcdhmc.json"
    "/etc/thorium/native-messaging-hosts/com.pir.browser.engine.json"
    "/etc/thorium/native-messaging-hosts/com.pirbrowser.bandwidth.json"
)

# List of user-level files to remove
USER_FILES=(
    "$HOME/.config/thorium/NativeMessagingHosts/com.pirbrowser.bandwidth.json"
    "$HOME/.config/thorium/NativeMessagingHosts/com.pirbrowser.bridge.json"
)

# List of directories to remove
DIRECTORIES=(
    "/home/jack/Documents/Pir Browser/core_bridge"
    "/opt/pir-browser"
    "$HOME/.local/share/pir-browser"
)

# Function to remove files and directories
remove_path() {
    if [ -e "$1" ]; then
        echo "Removing: $1"
        rm -rf "$1" 2>/dev/null || rm -rf "$1"
    else
        echo "Path not found, skipping: $1"
    fi
}

# Execute removal
# Note: Since I am an AI, I will provide the script for you to run if you prefer, 
# or I can attempt to run it if you give me permission.
# Many of these paths require sudo.

for file in "${SYSTEM_FILES[@]}"; do
    remove_path "$file"
done

for file in "${USER_FILES[@]}"; do
    remove_path "$file"
done

for dir in "${DIRECTORIES[@]}"; do
    remove_path "$dir"
done

# Remove launcher and lock scripts in root
remove_path "/home/jack/Documents/Pir Browser/run-pir-browser.sh"
remove_path "/home/jack/Documents/Pir Browser/lock_extensions.sh"

echo "Cleanup complete. Please restart Thorium to verify."
