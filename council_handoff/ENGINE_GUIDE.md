# Pir Engine: Technical Manual & RPC Guide (v7.5)

This document serves as the definitive technical reference for the custom `aria2c` engine utilized by the Pir Browser. 

## The Native Messaging Engine Guide
> [!CAUTION]
> **[LOCKED - DO NOT MODIFY]** 
> *The contents, flags, and manifest logic defined in this guide and its associated scripts are considered the mandatory foundation of the Pir Browser Suite. They may not be altered or optimized. If new features are needed, build around them.*

## 1. Native Messaging Protocol (IPC)

The Pir Bridge extension communicates with the engine host via the standard Chromium Native Messaging protocol.

### 4-Byte Length Header
*   **Format**: Every JSON message MUST be preceded by a **32-bit (4-byte) UInt32LE** length header.
*   **Endianness**: Little-endian (Standard x86/ARM).
*   **Logic**:
    ```javascript
    // Example Node.js Buffer handling
    const header = Buffer.alloc(4);
    header.writeUInt32LE(messageBuffer.length, 0);
    process.stdout.write(header);
    process.stdout.write(messageBuffer);
    ```

## 2. RPC API & Communication

The engine listens on `http://localhost:6800/jsonrpc` (default).

### Method: `aria2.addUri` (Header Injection)
Used for "Lazy Snatcher" link-cooking.
```bash
curl -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"qwer","method":"aria2.addUri", \
  "params":[["[URL]"], {"header":["Cookie: [COOKIE_DATA]", "User-Agent: PirBrowser/1.0"]}]}' \
  http://localhost:6800/jsonrpc
```

### Method: `aria2.tellStatus` (Live Telemetry)
Poll every 3s during active downloads.
```bash
curl -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"telem","method":"aria2.tellStatus","params":["[GID]"]}' \
  http://localhost:6800/jsonrpc
```

### Method: `aria2.pause` / `aria2.unpause`
```bash
# Pause
curl -d '{"jsonrpc":"2.0","id":"p","method":"aria2.pause","params":["[GID]"]}' http://localhost:6800/jsonrpc
# Resume
curl -d '{"jsonrpc":"2.0","id":"r","method":"aria2.unpause","params":["[GID]"]}' http://localhost:6800/jsonrpc
```

### Method: `aria2.changeOption` (Dynamic Throttling)
```bash
# Set 500K Limit
curl -d '{"jsonrpc":"2.0","id":"t","method":"aria2.changeOption","params":["[GID]", {"max-download-limit":"500K"}]}' http://localhost:6800/jsonrpc
# Remove Limit
curl -d '{"jsonrpc":"2.0","id":"u","method":"aria2.changeOption","params":["[GID]", {"max-download-limit":"0"}]}' http://localhost:6800/jsonrpc
```

### Method: `aria2.getGlobalStat`
```bash
curl -d '{"jsonrpc":"2.0","id":"stat","method":"aria2.getGlobalStat","params":[]}' http://localhost:6800/jsonrpc
```

## 3. Custom PIR Capabilities (Bespoke Flags)

The Pir Engine includes low-latency features specifically designed for high-concurrency fetching:

*   **`--enable-pir-cas-gate`**: Optimized piece selection for CAS-validated data streams.
*   **`--enable-pir-end-game`**: Bespoke End-Game sniping for TLS connections.
*   **`PIR_CAS_GATE_DEBUG=1`**: (Environment Variable) Enables stabilization telemetry for the `PieceBlockTracker`.

## 4. Identity & Safe Harbor

*   **Native Host ID**: `com.pir.browser.engine`
*   **Manifest Path**: `~/.config/thorium/NativeMessagingHosts/com.pir.browser.engine.json`
*   **Authorized Extension**: `jlclojpjcknjpnfkdmfmkaeklglmooaj` (Bridge)
