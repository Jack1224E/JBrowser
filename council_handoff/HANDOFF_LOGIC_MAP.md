# 🏴‍☠️ PIR BROWSER — ARCHITECTURAL HANDOFF MANIFEST (V7.1)

This document serves as the single, definitive 'Logic & Documentation Map' for the next engine session. It focuses purely on the data flow from the browser to the native engine, bypassing UI fluff.

---

## 1. THE MISSION
Transition the project from a localized cleanup phase into a specialized engine-direct session. The goal is to stabilize the **Native Messaging IPC** and the **Lazy Snatcher** interception logic to ensure consistent, authenticated download handoffs.

---

## 2. ARCHITECTURAL DECISIONS (CRAWL RESULTS)

### Core State (PROJECT_STATUS.md)
*   **Extension IDs**: Authorization is based on both Path-based IDs (for development/unpacked) and Key-based IDs (for stable/crx).
*   **Source of Truth**: The extension Ledger is the only place where authenticated headers (Cookie, UA) are stored by `requestId`.

### Extension Loading (walkthrough.md.resolved)
*   **Unpacked Priority**: Thorium is configured via `--load-extension` to prioritize the local `core_bridge/` development folders to bypass organizational policy restrictions during development.
*   **Engine Connectivity**: The "Disconnected" state was resolved by restoring the host manifest to point to the project-local `pir_host_launcher.sh`.

### Native Messaging (implementation_plan.md.resolved)
*   **Dual-ID Handshake**: The manifest authorizes both development and production extension IDs to ensure the pipe remains open regardless of how the browser is launched.
*   **Binary Fallback**: If a project-local `aria2c` binary is missing, the system `/usr/bin/aria2c` is used as the RPC engine.

### 'Cooked Link' Source (FDM_MASTER_LOGIC.md)
*   **Request Lifecycle**: The interceptor must wait for `onDeterminingFilename` to ensure the link is "cooked" (resolved from 302/301 redirects) and that its headers are fully tracked in the memory mapper.

---

## 3. COMPONENT LISTING (THE 'PIR BRIDGE' SUITE)

| Block | File Paths | Identity / ID |
|---|---|---|
| **The Interceptor (Bridge)** | `core_bridge/extension/manifest.json`<br>`core_bridge/extension/background.js` | **Path-based ID**: `jlclojpjcknjpnfkdmfmkaeklglmooaj`<br>**Key**: `MIIBIjANBg...IDAQAB` |
| **The UI (Switchboard)** | `core_bridge/switchboard/popup.html`<br>`core_bridge/switchboard/popup.js` | **Path-based ID**: `mfkdcklkfccghjcgndmfgeidccghccgh` |
| **The Plumbing (IPC)** | `~/.config/thorium/NativeMessagingHosts/com.pir.browser.engine.json` | **Native Host**: `com.pir.browser.engine` |
| **The Launcher** | `run-pir-browser.sh` | **Command**: `thorium-browser --load-extension="$BRIDGE,$SWITCHBOARD"` |

---

## 4. LOGIC EXPLANATION (THE 'SOUL' OF THE PROJECT)

### 🧩 THE 'LAZY SNATCHER'
**Objective**: Intercept downloads with full authentication context (Cookies, Referrer, UA) after redirects have been resolved.

1.  **The Ledger**: `webRequest.onBeforeRequest` and `onBeforeSendHeaders` capture request-specific metadata (Headers, PostData, Cookies) into a temporary Map indexed by `requestId`. Link redirects (302) update the ledger with the new destination URL.
2.  **Interception**: The extension hooks into `chrome.downloads.onDeterminingFilename`. At this stage, the link is "cooked"—the final destination URL is known and stabilized.
3.  **Lookup**: The Snatcher lookups the `finalUrl` in the Ledger. If found, it retrieves the "cooked" headers required to bypass 403 Forbidden blocks.
4.  **Handoff**: `chrome.downloads.cancel(downloadId)` is called to kill the browser's download. The "cooked" payload is shipped via `connectNative` to the engine.

### 💓 THE 'HEARTBEAT HANDSHAKE'
**Objective**: Maintain a persistent `stdio` pipe between Thorium and the Node.js/Electron engine while strictly following the Chrome Native Messaging protocol.

1.  **The Header**: Every message must be prefixed with a **32-bit (4-byte) Little-Endian integer** (`UInt32LE`) representing the length of the JSON string that follows.
2.  **Handshake Sequence**:
    *   **Browser**: Ships `{ "type": "handshake", "id": "1", ... }`.
    *   **Engine**: Must read the 4-byte header, parse the JSON, and immediately echo back `{ "id": "1", "result": "ok" }`.
3.  **The Response**: The response MUST also contain the 4-byte length header. Failure to provide this header, or providing an incorrect length, causes Thorium to terminate the process and show "Disconnected" in the UI.
4.  **Persistence**: The engine must not exit after a message—it must keep `stdin` open and wait for subsequent `create_downloads` tasks.

---

**[SIGNAL: LOGIC_MAP_GENERATED]** ⚓🏴‍☠️🏁
