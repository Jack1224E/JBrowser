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
