// Pirate Switchboard — Background Service Worker
// Architecture: Tiered Proxy System
// Default: Direct (No Proxy)

// ═══════════════════════════════════════════════════════
// PROXY CONFIGURATIONS
// ═══════════════════════════════════════════════════════
// NOTE: Most Indian ISP blocks are DNS-level. Enable "Secure DNS"
// in chrome://settings/security (Cloudflare 1.1.1.1) to bypass 90% of blocks.
// The proxy modes below handle the remaining deep-packet / IP-level blocks.

const PROXY_CONFIGS = {
  // ── DIRECT: No proxy. Raw ISP speed. (DEFAULT) ──
  direct: {
    mode: "pac_script",
    pacScript: {
      data: `function FindProxyForURL(url, host) { return "DIRECT"; }`
    }
  },

  // ── AUTO-SWITCH: Smart routing for pirate sites only ──
  // Uses Cloudflare DoH proxy for blocked sites, direct for everything else.
  // If WARP is running on localhost:40000, it will use that instead.
  auto: {
    mode: "pac_script",
    pacScript: {
      data: `
        function FindProxyForURL(url, host) {
          var direct = "DIRECT";
          // Blocked/pirate site domains
          var blocked = [
            "thepiratebay.org", "1337x.to", "rarbg.to",
            "fitgirl-repacks.site", "dodi-repacks.site",
            "steamrip.com", "steamunlocked.net",
            "buzzheavier.com", "gofile.io",
            "nyaa.si", "rutracker.org", "torrentgalaxy.to",
            "yts.mx", "eztv.re", "limetorrents.info",
            "katcr.co", "magnetdl.com"
          ];
          for (var i = 0; i < blocked.length; i++) {
            if (dnsDomainIs(host, blocked[i]) || dnsDomainIs(host, "." + blocked[i])) {
              // Try WARP first (localhost:40000), then public HTTPS proxies
              return "SOCKS5 127.0.0.1:40000; PROXY 127.0.0.1:8118; DIRECT";
            }
          }
          return direct;
        }
      `
    }
  },

  // ── WARP TUNNEL: All traffic through Cloudflare WARP ──
  // Requires: warp-cli set-mode proxy && warp-cli connect
  // Free, fast, reliable. Best option for full tunnel.
  warp: {
    mode: "fixed_servers",
    rules: {
      singleProxy: { scheme: "socks5", host: "127.0.0.1", port: 40000 }
    }
  },

  // ── TOR: Maximum anonymity via Tor network ──
  // Requires: tor service running (sudo systemctl start tor)
  tor: {
    mode: "fixed_servers",
    rules: {
      singleProxy: { scheme: "socks5", host: "127.0.0.1", port: 9050 }
    }
  },

  // ── CUSTOM TUNNEL: User-defined HTTP/SOCKS proxy ──
  // Default: Privoxy on 8118 (common setup with Tor)
  custom: {
    mode: "fixed_servers",
    rules: {
      singleProxy: { scheme: "http", host: "127.0.0.1", port: 8118 }
    }
  }
};

const MODE_LABELS = {
  direct:  { text: "D", color: "#343a40", name: "Direct (No Proxy)" },
  auto:    { text: "A", color: "#76a15d", name: "Auto-Switch (Smart)" },
  warp:    { text: "W", color: "#f48120", name: "WARP Tunnel" },
  tor:     { text: "T", color: "#6f42c1", name: "Tor (Anonymity)" },
  custom:  { text: "C", color: "#f0ad4e", name: "Custom Tunnel" }
};

// ═══════════════════════════════════════════════════════
// CORE LOGIC
// ═══════════════════════════════════════════════════════

async function applyProxy(mode) {
  const config = PROXY_CONFIGS[mode];
  if (!config) return;

  chrome.proxy.settings.set({ value: config, scope: "regular" }, () => {
    console.log(`[Switchboard] Proxy set to: ${mode}`);
    updateBadge(mode);
  });

  await chrome.storage.local.set({ currentMode: mode });
}

function updateBadge(mode) {
  const label = MODE_LABELS[mode];
  chrome.action.setBadgeText({ text: label.text });
  chrome.action.setBadgeBackgroundColor({ color: label.color });
}

// ── STARTUP: Default to DIRECT ──
chrome.runtime.onInstalled.addListener(async () => {
  const { currentMode } = await chrome.storage.local.get("currentMode");
  const initialMode = currentMode || "direct";  // DEFAULT: Direct
  applyProxy(initialMode);
});

chrome.runtime.onStartup.addListener(async () => {
  const { currentMode } = await chrome.storage.local.get("currentMode");
  applyProxy(currentMode || "direct");
});

// ── MESSAGE HANDLER ──
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.action === "setMode") {
    applyProxy(msg.mode).then(() => sendResponse({ success: true }));
    return true;
  }
  if (msg.action === "getMode") {
    chrome.storage.local.get("currentMode").then(res => sendResponse(res.currentMode || "direct"));
    return true;
  }
});
