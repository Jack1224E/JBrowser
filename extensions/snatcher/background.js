let nativePort = null;
const requestLedger = new Map();
const urlCookedMap = new Map();

// ═══════════════════════════════════════════════════════════
// §0  IDEMPOTENCY — Extension-Level URL Deduplication (3s TTL)
// ═══════════════════════════════════════════════════════════
const recentInterceptsMap = new Map(); // url → timestamp
const INTERCEPT_DEDUP_TTL_MS = 3000;

function isRecentDuplicate(url) {
    const now = Date.now();
    const lastSeen = recentInterceptsMap.get(url);
    if (lastSeen && (now - lastSeen) < INTERCEPT_DEDUP_TTL_MS) {
        return true;
    }
    recentInterceptsMap.set(url, now);
    // Housekeeping: evict expired entries
    for (const [key, ts] of recentInterceptsMap) {
        if ((now - ts) > INTERCEPT_DEDUP_TTL_MS) recentInterceptsMap.delete(key);
    }
    return false;
}

console.warn('[PIR_DIAG] Service worker loaded at:', new Date().toISOString());

// Diagnostic: log to storage for retrieval without DevTools
function diagLog(msg) {
    const line = `[${new Date().toISOString()}] ${msg}`;
    console.warn('[PIR_DIAG]', line);
    chrome.storage.local.get({ diagLog: [] }, (data) => {
        const log = data.diagLog || [];
        log.push(line);
        if (log.length > 100) log.shift();
        chrome.storage.local.set({ diagLog: log });
    });
}

diagLog('Service worker INITIALIZED');

// ═══════════════════════════════════════════════════════════
// §1  THE LEDGER — Track Request Metadata (cookies, referer)
// ═══════════════════════════════════════════════════════════
chrome.webRequest.onBeforeSendHeaders.addListener((details) => {
    let cookies = "";
    let referer = "";
    for (let header of details.requestHeaders) {
        if (header.name.toLowerCase() === "cookie") cookies += header.value + "; ";
        if (header.name.toLowerCase() === "referer") referer = header.value;
    }
    const cookedPayload = {
        url: details.url,
        cookies: cookies,
        referer: referer,
        time: Date.now()
    };
    requestLedger.set(details.requestId, cookedPayload);
    urlCookedMap.set(details.url, cookedPayload);
}, { urls: ["<all_urls>"] }, ["requestHeaders", "extraHeaders"]);

// ═══════════════════════════════════════════════════════════
// §2  THE SNATCHER — Intercept downloads, tag with requestId
// ═══════════════════════════════════════════════════════════
chrome.downloads.onDeterminingFilename.addListener((downloadItem, suggest) => {
    const finalUrl = downloadItem.finalUrl || downloadItem.url;

    // IDEMPOTENCY GATE: Suppress Chrome's duplicate event fires
    if (isRecentDuplicate(finalUrl)) {
        diagLog(`DUPLICATE SUPPRESSED (extension-level): ${finalUrl}`);
        return;
    }

    // Generate a cryptographic requestId for this interception
    const requestId = crypto.randomUUID();
    diagLog(`onDeterminingFilename FIRED! requestId=${requestId} URL=${finalUrl}`);

    chrome.downloads.cancel(downloadItem.id, () => {
        if (chrome.runtime.lastError) {
            diagLog(`downloads.cancel ERROR: ${chrome.runtime.lastError.message}`);
        } else {
            diagLog(`downloads.cancel OK for id: ${downloadItem.id}`);
        }
    });

    const cookedPayload = urlCookedMap.get(finalUrl) || urlCookedMap.get(downloadItem.url) || { cookies: "", referer: "" };

    console.warn("\n==============================================");
    console.warn("[PIR_INTERCEPT_LOG] ✅ COOKED LINK CAUGHT!");
    console.warn(`[PIR_INTERCEPT_LOG] requestId: ${requestId}`);
    console.warn("[PIR_INTERCEPT_LOG] FINAL URL:", finalUrl);
    console.warn("==============================================\n");

    startNativeDownload({
        requestId: requestId,
        url: finalUrl,
        filename: downloadItem.filename,
        httpCookies: cookedPayload.cookies,
        httpReferer: cookedPayload.referer
    });
});

diagLog('onDeterminingFilename listener REGISTERED');

// ═══════════════════════════════════════════════════════════
// §3  THE BRIDGE — Ship to Native Messaging Host
// ═══════════════════════════════════════════════════════════
function startNativeDownload(payload) {
    diagLog(`startNativeDownload called. requestId=${payload.requestId} URL=${payload.url}`);

    if (!nativePort) {
        diagLog('Creating new native port to com.pir.browser.engine...');
        try {
            nativePort = chrome.runtime.connectNative('com.pir.browser.engine');
            diagLog('connectNative() returned successfully');

            nativePort.onMessage.addListener((response) => {
                diagLog(`Native response: ${JSON.stringify(response)}`);
            });
            nativePort.onDisconnect.addListener(() => {
                const err = chrome.runtime.lastError;
                diagLog(`Native port DISCONNECTED. Error: ${err ? err.message : 'none'}`);
                nativePort = null;
            });
        } catch (e) {
            diagLog(`connectNative() THREW: ${e.message}`);
            nativePort = null;
            return;
        }
    }

    const msg = {
        type: 'create_downloads',
        id: payload.requestId,
        create_downloads: {
            downloads: [
                {
                    requestId: payload.requestId,
                    originalUrl: payload.url,
                    url: payload.url,
                    filename: payload.filename || "",
                    directory: "",
                    httpCookies: payload.httpCookies,
                    httpReferer: payload.httpReferer,
                    userAgent: navigator.userAgent
                }
            ]
        }
    };

    diagLog(`Sending message to native port: ${JSON.stringify(msg).substring(0, 250)}...`);

    try {
        nativePort.postMessage(msg);
        diagLog('postMessage() sent successfully');
    } catch (e) {
        diagLog(`postMessage() THREW: ${e.message}`);
        nativePort = null;
    }
}
