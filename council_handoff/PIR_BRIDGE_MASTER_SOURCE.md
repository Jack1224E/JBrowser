### /home/jack/Documents/Pir Browser/core_bridge/extension/manifest.json
```json
{
  "manifest_version": 3,
  "name": "Pir Downloader",
  "version": "1.0",
  "key": "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAz3O3dScQwCyjuWdIkZwqHm6n9m8qpRIkMs6vKNSX65maXHZz+BuzmJyNR/cQO3gfNRXbaB8Wn+qnQItcF4n3LOgG8ltaHg17f+AqH7xlZzKOUl5bkL6myMaDdfnovKlf0wSWATO1u/BmWXwXLw0Kq8HFrY+w+ntoC+OZ7BMZXgjaF6a6Q9b/UaEBQdf4pnQ8VZ9hn+qFibwQFHrd1Z6rYwLZ1PHzkqUnqsbZ1fhK2S1JIxnS2fOSkx0M/9If+VHqEURqMjtyyf56Z2WmxmvBh0LtA1zMvrOoqWOWCE1O74I1qJxPkGpRe8irG5dmBkZIAAKSHIDoi4NljyLtqRyF9wIDAQAB",
  "description": "High-performance pirate loot fetcher for Pir Browser.",
  "permissions": [
    "downloads",
    "nativeMessaging",
    "storage"
  ],
  "background": {
    "service_worker": "background.js"
  },
  "action": {
    "default_popup": "popup.html",
    "default_icon": "icons/icon128.png"
  },
  "icons": {
    "128": "icons/icon128.png"
  }
}
```

### /home/jack/Documents/Pir Browser/core_bridge/extension/background.js
```javascript
let nativePort = null;
let currentDownload = null;

chrome.downloads.onCreated.addListener((downloadItem) => {
    // Cancel the default download immediately
    chrome.downloads.cancel(downloadItem.id);
    
    currentDownload = {
        id: downloadItem.id,
        url: downloadItem.url,
        filename: downloadItem.filename,
        totalBytes: downloadItem.totalBytes,
        mime: downloadItem.mime
    };

    // Open the popup or a custom tab to show the "IDM" UI
    // Note: POPUP usually requires user action, so we might open a small window instead
    chrome.windows.create({
        url: 'popup.html',
        type: 'popup',
        width: 480,
        height: 600
    });
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.type === 'GET_DOWNLOAD_INFO') {
        sendResponse(currentDownload);
    } else if (message.type === 'START_DOWNLOAD') {
        startNativeDownload(message.payload);
    } else if (message.type === 'CANCEL_DOWNLOAD') {
        cancelNativeDownload();
    }
});

function startNativeDownload(payload) {
    if (!nativePort) {
        nativePort = chrome.runtime.connectNative('com.pir.browser.engine');
        nativePort.onMessage.addListener((response) => {
            chrome.runtime.sendMessage({ type: 'PROGRESS_UPDATE', payload: response });
        });
        nativePort.onDisconnect.addListener(() => {
            console.log('Native messaging port disconnected');
            nativePort = null;
        });
    }

    nativePort.postMessage({
        command: 'start',
        url: payload.url,
        filename: payload.filename,
        directory: payload.directory
    });
}

function cancelNativeDownload() {
    if (nativePort) {
        nativePort.postMessage({ command: 'stop' });
    }
}
```

### /home/jack/Documents/Pir Browser/core_bridge/switchboard/popup.html
```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            width: 300px;
            font-family: 'Segoe UI', system-ui, sans-serif;
            background: #f4ecd8;
            color: #022c22;
        }
        .header {
            background: linear-gradient(135deg, #022c22 0%, #034a38 100%);
            color: #f4ecd8;
            padding: 14px 16px;
            font-size: 15px;
            font-weight: 700;
            letter-spacing: 1px;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .header::before { content: "⚓"; font-size: 18px; }

        .status-bar {
            background: #e8dcc4;
            padding: 8px 16px;
            font-size: 11px;
            color: #6b5b3e;
            border-bottom: 1px solid #d4c5a5;
        }
        .status-bar .active-mode {
            font-weight: 700;
            color: #022c22;
        }

        .mode-list { padding: 8px; }

        .mode-btn {
            display: flex;
            align-items: center;
            gap: 10px;
            width: 100%;
            padding: 10px 12px;
            margin-bottom: 4px;
            border: 2px solid transparent;
            border-radius: 8px;
            background: #fff;
            color: #022c22;
            cursor: pointer;
            font-size: 13px;
            font-weight: 500;
            transition: all 0.15s ease;
            text-align: left;
        }
        .mode-btn:hover {
            background: #e8f5e9;
            border-color: #76a15d;
            transform: translateX(3px);
        }
        .mode-btn.active {
            background: #022c22;
            color: #f4ecd8;
            border-color: #76a15d;
            font-weight: 700;
        }
        .mode-btn .dot {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            flex-shrink: 0;
        }
        .mode-btn .desc {
            font-size: 10px;
            opacity: 0.7;
            font-weight: 400;
            display: block;
            margin-top: 2px;
        }

        .divider {
            height: 1px;
            background: #d4c5a5;
            margin: 4px 12px;
        }

        .section-label {
            font-size: 10px;
            font-weight: 700;
            color: #8a7a5c;
            text-transform: uppercase;
            letter-spacing: 1.5px;
            padding: 6px 16px 2px;
        }

        .footer {
            padding: 8px 16px;
            font-size: 10px;
            color: #8a7a5c;
            text-align: center;
            border-top: 1px solid #d4c5a5;
        }
        .footer a {
            color: #034a38;
            text-decoration: none;
            font-weight: 600;
        }
    </style>
</head>
<body>
    <div class="header">SWITCHBOARD</div>
    <div class="status-bar">
        Active: <span class="active-mode" id="activeLabel">Loading...</span>
    </div>

    <div class="section-label">Quick Modes</div>
    <div class="mode-list">
        <button class="mode-btn" data-mode="direct">
            <span class="dot" style="background: #343a40"></span>
            <div>🌑 Direct (No Proxy)
                <span class="desc">Raw ISP speed. No tunneling.</span>
            </div>
        </button>
        <button class="mode-btn" data-mode="auto">
            <span class="dot" style="background: #76a15d"></span>
            <div>🏴‍☠️ Auto-Switch (Smart)
                <span class="desc">Routes only blocked/pirate sites through tunnel.</span>
            </div>
        </button>
    </div>

    <div class="divider"></div>
    <div class="section-label">Tunnel Services</div>
    <div class="mode-list">
        <button class="mode-btn" data-mode="warp">
            <span class="dot" style="background: #f48120"></span>
            <div>🔥 WARP Tunnel (Cloudflare)
                <span class="desc">Free & fast. Requires warp-cli setup.</span>
            </div>
        </button>
        <button class="mode-btn" data-mode="tor">
            <span class="dot" style="background: #6f42c1"></span>
            <div>🛡️ Tor (Anonymity)
                <span class="desc">Max privacy. Requires tor service.</span>
            </div>
        </button>
        <button class="mode-btn" data-mode="custom">
            <span class="dot" style="background: #f0ad4e"></span>
            <div>⚙️ Custom Tunnel
                <span class="desc">Your own proxy (default: HTTP 127.0.0.1:8118).</span>
            </div>
        </button>
    </div>

    <div class="footer">
        <a href="https://one.one.one.one/" target="_blank">Get Cloudflare WARP →</a><br>
        Pir Browser v1.0
    </div>

    <script src="popup.js"></script>
</body>
</html>
```

### /home/jack/Documents/Pir Browser/core_bridge/switchboard/popup.js
```javascript
// Pirate Switchboard — Popup Controller

const MODE_LABELS = {
  direct:  "🌑 Direct (No Proxy)",
  auto:    "🏴‍☠️ Auto-Switch (Smart)",
  warp:    "🔥 WARP Tunnel",
  tor:     "🛡️ Tor (Anonymity)",
  custom:  "⚙️ Custom Tunnel"
};

document.addEventListener("DOMContentLoaded", () => {
  // Get current mode
  chrome.runtime.sendMessage({ action: "getMode" }, (mode) => {
    const current = mode || "direct";
    highlightActive(current);
    document.getElementById("activeLabel").textContent = MODE_LABELS[current] || current;
  });

  // Button handlers
  document.querySelectorAll(".mode-btn").forEach(btn => {
    btn.addEventListener("click", () => {
      const mode = btn.dataset.mode;
      chrome.runtime.sendMessage({ action: "setMode", mode }, () => {
        highlightActive(mode);
        document.getElementById("activeLabel").textContent = MODE_LABELS[mode] || mode;
        // Close popup after a brief visual confirmation
        setTimeout(() => window.close(), 300);
      });
    });
  });
});

function highlightActive(mode) {
  document.querySelectorAll(".mode-btn").forEach(btn => {
    btn.classList.toggle("active", btn.dataset.mode === mode);
  });
}
```

### /home/jack/.config/thorium/NativeMessagingHosts/com.pir.browser.engine.json
```json
{
  "name": "com.pir.browser.engine",
  "description": "Pir Browser Download Engine Native Messaging Host",
  "path": "/home/jack/Documents/Pir Browser/core_bridge/pir_host_launcher.sh",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://jlclojmcifniclnahffcmhocbccljfgc/",
    "chrome-extension://mfkdafmmppeidkmpnfjminnjimjikigl/",
    "chrome-extension://hfcoolpdkaomnejbjoaekedlfgflgoel/",
    "chrome-extension://ddkjiahejlhfcafbddmgiahcphecmpfh/",
    "chrome-extension://dnpahafmecohlldddcjkhbhagjkmibjk/",
    "chrome-extension://hhjnfpeaggjiapefhginmnlhaifoddee/"
  ]
}
```

### /home/jack/Documents/Pir Browser/run-pir-browser.sh
```bash
#!/bin/bash
# Pir Browser — Ultimate Launcher (v6.5.2)

# 1. Start or Verify the Engine (aria2c RPC)
if ! pgrep -x "aria2c" > /dev/null; then
    echo "Starting aria2c engine..."
    ./scripts/aria2c --enable-rpc --rpc-listen-all --rpc-allow-origin-all --daemon
else
    echo "aria2c engine is already running."
fi

# 2. Extensions Setup (Safe Harbor)
BRIDGE="/home/jack/.config/thorium/PirExtensions/pir_bridge"
SWITCHBOARD="/home/jack/.config/thorium/PirExtensions/switchboard"

# 3. Launch Thorium with Armored Extensions
# Sync IDs: jlclojmcifniclnahffcmhocbccljfgc and mfkdafmmppeidkmpnfjminnjimjikigl
echo "Launching Thorium with Pir Bridge..."
"/home/jack/Documents/Pir Browser/_legacy/binaries/Thorium_Browser_138.0.7204.303_AVX2.AppImage" \
  "file:///home/jack/Documents/Pir%20Browser/dashboard.html" \
  --load-extension="$BRIDGE,$SWITCHBOARD"
```

### /home/jack/Documents/Pir Browser/core_bridge/pir_host_launcher.sh
```bash
#!/bin/bash
echo "[$(date)] pir_host_launcher.sh EXECUTED" >> /tmp/pir_host_launch.log
exec node "/home/jack/Documents/Pir Browser/core_bridge/pir_host.js" "$@" 2>> /tmp/pir_host_launch.log
```

### /home/jack/Documents/Pir Browser/core_bridge/pir_host.js
```javascript
#!/usr/bin/env node
/**
 * PIR BRIDGE — Native Messaging Host (Pure Node.js, No Electron)
 * 
 * Protocol: Chrome Native Messaging (4-byte LE length header + JSON)
 * Handles: handshake, create_downloads → forwards to aria2c JSON-RPC
 */

const http = require('http');

const ARIA2_RPC = 'http://127.0.0.1:6800/jsonrpc';

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

function handleMessage(msg) {
    if (msg.type === 'handshake') {
        process.stderr.write('[PirHost] Handshake received. Replying OK.\n');
        sendMessage({ id: msg.id, result: 'ok' });
        return;
    }

    if (msg.type === 'create_downloads' && msg.create_downloads) {
        const downloads = msg.create_downloads.downloads || [];
        process.stderr.write('[PirHost] Received ' + downloads.length + ' download(s).\n');

        for (const dl of downloads) {
            sendToAria2(dl, msg.id);
        }
        return;
    }

    // Generic ack for anything else with an id
    if (msg.id) {
        sendMessage({ id: msg.id, result: 'ok' });
    }
}

// ═══════════════════════════════════════════
// §3  ARIA2C JSON-RPC BRIDGE
// ═══════════════════════════════════════════

function sendToAria2(dl, requestId) {
    const headers = [];
    if (dl.httpCookies) headers.push('Cookie: ' + dl.httpCookies);
    if (dl.httpReferer) headers.push('Referer: ' + dl.httpReferer);
    if (dl.userAgent)   headers.push('User-Agent: ' + dl.userAgent);

    const rpc = {
        jsonrpc: '2.0',
        id: 'pir-' + Date.now(),
        method: 'aria2.addUri',
        params: [
            [dl.url || dl.originalUrl],
            {
                header: headers,
                'max-connection-per-server': '16',
                split: '16'
            }
        ]
    };

    const body = JSON.stringify(rpc);
    const url = new URL(ARIA2_RPC);

    const req = http.request({
        hostname: url.hostname,
        port: url.port,
        path: url.pathname,
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(body)
        }
    }, (res) => {
        let data = '';
        res.on('data', (c) => data += c);
        res.on('end', () => {
            process.stderr.write('[PirHost] aria2 response: ' + data + '\n');
            try {
                const parsed = JSON.parse(data);
                sendMessage({ id: requestId, result: parsed.result || 'ok' });
            } catch (e) {
                sendMessage({ id: requestId, result: 'ok' });
            }
        });
    });

    req.on('error', (e) => {
        process.stderr.write('[PirHost] aria2 error: ' + e.message + '\n');
        sendMessage({ id: requestId, error: 'aria2_unreachable' });
    });

    req.write(body);
    req.end();
}

process.stderr.write('[PirHost] Native Messaging Host started.\n');
```
