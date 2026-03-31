#!/bin/bash

# JBrowser Vault Setup Script
# Verifies and guides the restoration of custom binaries.

set -e

# Configuration
VAULT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$VAULT_ROOT/bin"
REQUIRED_BINS=("aria2c" "Thorium_Browser_138.0.7204.303_AVX2.AppImage")

echo "🔗 JBrowser Vault Setup"
echo "----------------------"

# Ensure bin directory exists
mkdir -p "$BIN_DIR"

MISSING=0

for bin in "${REQUIRED_BINS[@]}"; do
    if [ ! -f "$BIN_DIR/$bin" ]; then
        echo "❌ Missing: $bin"
        MISSING=1
    else
        echo "✅ Found: $bin"
        chmod +x "$BIN_DIR/$bin"
    fi
done

echo ""

if [ $MISSING -eq 1 ]; then
    echo "⚠️  Important Step Required:"
    echo "This project uses custom binaries that are too large for GitHub status status status status status status status p."
    echo "Please download the custom 'aria2c' and 'Thorium' assets from the GitHub Releases page"
    echo "and place them in the '$BIN_DIR' directory."
    echo ""
    echo "Once placed, run this script again to verify and set permissions."
    exit 1
else
    echo "🚀 All binaries verified. JBrowser is ready for launch!"
    exit 0
fi
