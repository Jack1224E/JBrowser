# 🏴‍☠️ JBrowser Master Debug Audit & Scrutiny Report (FULL CONTENT v2)

This document contains a full technical snapshot of the current integration failure between the **Thorium Browser**, the **Native Messaging Bridge (Postman)**, and the **Switchboard (Downloader)**.

## 🧪 Debugging Hypothesis (Why it fails)

### 1. The "Ghost Manifest" Failure
In Ghost Mode, the launcher creates a symlink in `~/.config/thorium/NativeMessagingHosts/` pointing to a temporary JSON manifest in a RAM disk (`/tmp`). 
*   **Hypothesis**: A syntax error in `run-pir-browser.sh` causes the script to exit or malfunction before the browser fully registers the host. Additionally, if the symlink is deleted early by the bash `trap`, the browser loses the bridge mid-launch.

### 2. The "Silent Crash" of PirHost (ReferenceError)
*   **Discovery**: `scripts/pir_host.js` currently uses a `log()` function that is **not defined** in the file.
*   **Hypothesis**: When the extension attempts to connect, the Node.js process starts, immediately hits `log()`, throws a `ReferenceError`, and exits. This explains why `/tmp/jbrowser_bridge.log` was never created.

### 3. The "Pinning Resistance"
*   **Hypothesis**: Thorium v138 treats the first launch as a "Pristine Session." It ignores `initial_preferences` if it doesn't find them in the exact expected format or if it decides to generate its own `Preferences` file after the extensions are loaded.

---

## 📂 FULL FILE CONTENTS

### 1. `scripts/run-pir-browser.sh`
```bash
#!/bin/bash
# Pir Browser — Ghost Launcher (v10.2.0)
# [VOLATILE MODE ACTIVE - EPHEMERAL profile in RAM]

# 1. Start or Verify the Engine (aria2c RPC)
if ! pgrep -x "aria2c" > /dev/null; then
    echo "[Launcher] Starting aria2c engine..."
    chmod +x "/home/jack/Documents/JBrowser/bin/aria2c"
    "/home/jack/Documents/JBrowser/bin/aria2c" --enable-rpc --rpc-listen-all --rpc-allow-origin-all --daemon
else
    echo "[Launcher] aria2c engine is already running."
fi

# 2. Workspace & Ephemeral Profile Initialization
BASE_DIR="/home/jack/Documents/JBrowser"
THORIUM="${BASE_DIR}/bin/Thorium_Browser_138.0.7204.303_AVX2.AppImage"
DASHBOARD="file://${BASE_DIR}/UI/dashboard.html"
DASHBOARD="${DASHBOARD// /%20}"

# Create a unique, volatile temporary workspace in RAM
TEMP_PROFILE=$(mktemp -d /tmp/jbrowser_vault.XXXXXX)
SYSTEM_HOSTS_DIR="${HOME}/.config/thorium/NativeMessagingHosts"
mkdir -p "${SYSTEM_HOSTS_DIR}"

# 3. The Vanish (Automatic Cleanup Trap)
trap 'rm -f "${SYSTEM_HOSTS_DIR}/com.pir.browser.engine.json"; rm -rf "${TEMP_PROFILE}"' EXIT

BRIDGE_ID="ajfepmgaamkbdfofhkhfklpabmfogmca"
SWITCH_ID="jbbghkkfkmcdpnbekmcpikclpfcbeeej"

# 4. Triple-Seed Preferences (Extension Pinning & Dashboard)
# Chromium versions vary: initial_preferences, master_preferences, or Preferences
echo "[Launcher] Seeding preferences into ${TEMP_PROFILE}"
cp "${BASE_DIR}/manifests/initial_preferences" "${TEMP_PROFILE}/initial_preferences"
cp "${BASE_DIR}/manifests/initial_preferences" "${TEMP_PROFILE}/master_preferences"
mkdir -p "${TEMP_PROFILE}/Default"
cp "${BASE_DIR}/manifests/initial_preferences" "${TEMP_PROFILE}/Default/Preferences"

# 5. Tactical Native Messaging Host (RAM-to-System Link)
RAM_MANIFEST="${TEMP_PROFILE}/com.pir.browser.engine.json"
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

ln -sfn "$RAM_MANIFEST" "${SYSTEM_HOSTS_DIR}/com.pir.browser.engine.json"

# 6. Anti-Space Symlink Workaround for AppImage Extensions
mkdir -p /tmp/pir_suite
ln -sfn "${BASE_DIR}/extensions/snatcher" "/tmp/pir_suite/bridge"
ln -sfn "${BASE_DIR}/extensions/switchboard" "/tmp/pir_suite/switchboard"

# 7. Ghost Launch
cd "${BASE_DIR}" || exit 1
echo "[Launcher] Launching Pir Browser (Ghost Mode)..."
echo "[Launcher] Profile: ${TEMP_PROFILE}"

"${THORIUM}" \
  --user-data-dir="${TEMP_PROFILE}" \
  --load-extension="/tmp/pir_suite/bridge,/tmp/pir_suite/switchboard" \
  --remote-debugging-port=9222 \
  --no-first-run \
  --no-default-browser-check \
  --homepage="${DASHBOARD}" \
  "${DASHBOARD}"
```

### 2. `scripts/pir_host.js`
```javascript
#!/usr/bin/env node
/**
 * PIR BRIDGE — Native Messaging Host (Pure Node.js, No Electron)
 *
 * Protocol: Chrome Native Messaging (4-byte LE length header + JSON)
 * Handles: handshake, create_downloads → logs URLs to bridge_test_log.txt
 */

const fs = require('fs');
const net = require('net');
const http = require('http');
const { spawn } = require('child_process');

const ARIA2_RPC_URL = 'http://127.0.0.1:6800/jsonrpc';
const SWITCHBOARD_BIN = '/home/jack/Documents/JBrowser/pir_switchboard/build/linux/x64/debug/bundle/pir_switchboard';

function getSocketPath() {
    const xdgDir = process.env.XDG_RUNTIME_DIR;
    return xdgDir ? `${xdgDir}/jbrowser/bridge.sock` : '/tmp/jbrowser/bridge.sock';
}

// ═══════════════════════════════════════════
// §1  NATIVE MESSAGING PROTOCOL
// ═══════════════════════════════════════════

function sendMessage(msg) {
    const json = JSON.stringify(msg);
    const buf = Buffer.from(json, 'utf8');
    const header = Buffer.alloc(4);
    header.writeUInt32LE(buf.length, 0);
    process.stdout.write(header);
    process.stdout.write(buf);
}

let inputBuffer = Buffer.alloc(0);

process.stdin.on('data', (chunk) => {
    inputBuffer = Buffer.concat([inputBuffer, chunk]);

    while (inputBuffer.length >= 4) {
        const length = inputBuffer.readUInt32LE(0);
        if (inputBuffer.length >= 4 + length) {
            const msgBuf = inputBuffer.subarray(4, 4 + length);
            inputBuffer = inputBuffer.subarray(4 + length);

            try {
                const message = JSON.parse(msgBuf.toString('utf8'));
                process.stderr.write('[PirHost] INCOMING: ' + JSON.stringify(message) + '\n');
                handleMessage(message);
            } catch (e) {
                process.stderr.write('[PirHost] Parse error: ' + e.message + '\n');
            }
        } else {
            break;
        }
    }
});

// ═══════════════════════════════════════════
// §2  MESSAGE HANDLER
// ═══════════════════════════════════════════

async function handleMessage(msg) {
    log(`Handling message: ${msg.type || 'unknown'}`);
    if (msg.type === 'handshake') {
        log('Handshake received. Replying OK.');
        sendMessage({ id: msg.id, result: 'ok' });
        return;
    }

    if (msg.type === 'create_downloads' && msg.create_downloads) {
        const downloads = msg.create_downloads.downloads || [];
        log(`Processing ${downloads.length} download(s).`);

        for (const dl of downloads) {
            const url = dl.url || dl.originalUrl;
            if (!url) continue;

            const payload = { 
                url: url, 
                headers: dl.headers || {},
                timestamp: new Date().toISOString()
            };
            
            log(`Download request for URL: ${url}`);
            
            // ═══════════════════════════════════════════
            // § OPTIMISTIC IPC BRIDGE (UDS)
            // ═══════════════════════════════════════════
            const udsSuccess = await attemptUdsHandoff(payload);
            log(`UDS Handoff result: ${udsSuccess}`);
            
            if (!udsSuccess) {
                log('UDS failed. Attempting Switchboard launch.');
                attemptSwitchboardLaunch();
                
                log('Falling back to HTTP RPC.');
                await attemptRpcFallback(url, payload.headers);
            }
        }

        sendMessage({ id: msg.id, result: 'ok' });
        return;
    }

    if (msg.id) sendMessage({ id: msg.id, result: 'ok' });
}

function attemptSwitchboardLaunch() {
    try {
        log(`Checking Switchboard at: ${SWITCHBOARD_BIN}`);
        if (fs.existsSync(SWITCHBOARD_BIN)) {
            log('Binary found. Spawning...');
            const child = spawn(SWITCHBOARD_BIN, [], {
                detached: true,
                stdio: 'ignore'
            });
            child.on('error', (err) => {
                log(`Spawn error event: ${err.message}`);
            });
            child.unref();
            log('Switchboard spawn called (detached).');
        } else {
            log(`ERROR: Switchboard binary NOT found at ${SWITCHBOARD_BIN}`);
        }
    } catch (e) {
        log(`CRITICAL LAUNCH ERROR: ${e.message}`);
    }
}

async function attemptUdsHandoff(payload) {
    const socketPath = getSocketPath();
    log(`Attempting UDS connection to: ${socketPath}`);
    return new Promise((resolve) => {
        const client = net.createConnection({ path: socketPath }, () => {
            client.write(JSON.stringify(payload));
            client.end();
            log('Socket handoff successful.');
            resolve(true);
        });

        client.setTimeout(200);
        client.on('timeout', () => {
            client.destroy();
            resolve(false);
        });

        client.on('error', () => {
            resolve(false);
        });
    });
}

function attemptRpcFallback(url, headers) {
    return new Promise((resolve) => {
        const rpcPayload = JSON.stringify({
            jsonrpc: '2.0',
            id: 'pir-fallback-' + Date.now(),
            method: 'aria2.addUri',
            params: [[url], { header: Object.entries(headers).map(([k, v]) => `${k}: ${v}`) }]
        });

        const req = http.request(ARIA2_RPC_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }
        }, (res) => {
            resolve(true);
        });

        req.on('error', (e) => {
            process.stderr.write(`[PirHost] RPC Fallback Failed: ${e.message}\n`);
            resolve(false);
        });

        req.write(rpcPayload);
        req.end();
    });
}

process.stderr.write('[PirHost] Native Messaging Host started.\n');
```

### 3. `scripts/pir_host_launcher.sh`
```bash
#!/bin/bash
# JBrowser Native Host Launcher

set -euo pipefail

# Log for debugging
echo "[$(date)] pir_host_launcher.sh EXECUTED" >> /tmp/pir_bridge_debug.log

# Ensure we use the correct node binary
exec node "/home/jack/Documents/JBrowser/scripts/pir_host.js" "$@" 2>> /tmp/pir_bridge_debug.log
```

### 4. `manifests/initial_preferences`
```json
{
  "profile": {
    "content_settings": {
      "exceptions": {
        "notifications": {
          "https://*,*": {
            "setting": 1
          }
        }
      }
    }
  },
  "extensions": {
    "settings": {
      "ajfepmgaamkbdfofhkhfklpabmfogmca": {
        "toolbar_pin": "force_pinned"
      },
      "jbbghkkfkmcdpnbekmcpikclpfcbeeej": {
        "toolbar_pin": "force_pinned"
      }
    }
  },
  "session": {
    "restore_on_startup": 4,
    "startup_urls": [
      "https://google.com"
    ]
  },
  "browser": {
    "has_seen_welcome_page": true
  }
}
```

### 5. `scripts/diagnose_suite.sh`
```bash
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
```

---




> "I am troubleshooting a complex integration between a Thorium browser, a Node.js Native Messaging Host, and a Flutter application. Currently, the browser fails to pin specified extensions and fails to auto-launch the native bridge when a download is triggered.
>
> I have attached a file called `MASTER_DEBUG_AUDIT.md` which contains the current source code of all relevant scripts and our current failure hypothesis.
>
> **Task**: Scrutinize the provided code and identify:
> 1. Exact syntax errors in the bash launcher (`run-pir-browser.sh`).
> 2. Logic errors or missing functions in the Node.js bridge (`pir_host.js`).
> 3. Why the `initial_preferences` file structure might be failing to force extension pins in Thorium v138.
> 4. Potential permission or path issues preventing the Flutter binary (Switchboard) from spawning.
>
> Do not fix the code yet, only provide a detailed list of identified culprits and a verified path to resolution."
