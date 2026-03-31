let nativePort = null;
const requestLedger = new Map();
const urlCookedMap = new Map();

// 1. The Ledger: Track Request Metadata
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
    urlCookedMap.set(details.url, cookedPayload); // Backup by URL
}, { urls: ["<all_urls>"] }, ["requestHeaders", "extraHeaders"]);

// 2. The Snatcher: Intercept after redirects
chrome.downloads.onDeterminingFilename.addListener((downloadItem, suggest) => {
    chrome.downloads.cancel(downloadItem.id);
    
    // COOK THE LINK
    let finalUrl = downloadItem.finalUrl || downloadItem.url;
    let cookedPayload = urlCookedMap.get(finalUrl) || urlCookedMap.get(downloadItem.url) || { cookies: "", referer: "" };
    
    console.warn("\n==============================================");
    console.warn("[PIR_INTERCEPT_LOG] ✅ COOKED LINK CAUGHT!");
    console.warn("[PIR_INTERCEPT_LOG] FINAL URL:", finalUrl);
    console.warn("==============================================\n");

    // Ship "Cooked Link" to the aria2c Engine securely
    startNativeDownload({
        url: finalUrl,
        filename: downloadItem.filename,
        httpCookies: cookedPayload.cookies,
        httpReferer: cookedPayload.referer
    });
});

// 3. The Bridge
function startNativeDownload(payload) {
    if (!nativePort) {
        nativePort = chrome.runtime.connectNative('com.pir.browser.engine');
        nativePort.onMessage.addListener((response) => {
            console.log('[Native Messaging Engine] Update:', response);
        });
        nativePort.onDisconnect.addListener(() => {
            console.warn('[Native Messaging Engine] Disconnected:', chrome.runtime.lastError);
            nativePort = null;
        });
    }

    nativePort.postMessage({
        type: 'create_downloads',
        id: 'ext-' + Date.now(),
        create_downloads: {
            downloads: [
                {
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
    });
}
