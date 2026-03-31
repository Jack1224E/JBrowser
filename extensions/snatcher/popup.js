document.addEventListener('DOMContentLoaded', () => {
    // 1. Pause All
    const pauseAllBtn = document.getElementById('pauseAll');
    pauseAllBtn.addEventListener('click', () => {
        pauseAllBtn.classList.toggle('active');
        if (pauseAllBtn.classList.contains('active')) {
            pauseAllBtn.textContent = "Resume catching downloads from all sites";
        } else {
            pauseAllBtn.textContent = "Pause to catch downloads from all sites";
        }
        // In the future: chrome.storage.local.set({ pauseAll: ... })
    });

    // 2. Pause Site
    const pauseSiteBtn = document.getElementById('pauseSite');
    pauseSiteBtn.addEventListener('click', () => {
        pauseSiteBtn.classList.toggle('active');
        if (pauseSiteBtn.classList.contains('active')) {
            pauseSiteBtn.textContent = "Catch downloads from this site";
        } else {
            pauseSiteBtn.textContent = "Don't catch downloads from this site";
        }
        // In the future: chrome.tabs.query ...
    });

    // 3. Options
    document.getElementById('options').addEventListener('click', () => {
        // chrome.runtime.openOptionsPage();
        alert("Options pane coming soon in v1.1");
    });

    // 4. Help
    document.getElementById('help').addEventListener('click', () => {
        alert("Pir Downloader Support - ⚓ Yarr!");
    });
});
