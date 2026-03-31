# JBrowser Vault

A high-performance, orchestrated browser environment powered by Thorium and a custom native download engine.

## 🚀 Overview
JBrowser is a specialized browser suite designed for maximum technical efficiency. It integrates the Chromium-based **Thorium Browser** with a custom native messaging bridge and a multi-threaded engine to provide a seamless, high-speed download and proxy orchestration experience.

## ✨ Key Features
- **Direct Link Interception**: Automated capture of download triggers via browser extensions.
- **Low-Latency RPC Bridge**: A custom-built native messaging host for real-time communication between the browser and the system.
- **Smart Engine Orchestration**: Powered by a headless download manager for ultra-fast, robust data transfers.
- **Custom Startup Dashboard**: Features "The Meadow," a sleek, optimized landing page for immediate workspace access.
- **Portable Environment**: Fully self-contained vault architecture for consistent deployment.

## 🏗️ Technical Architecture
- **Browser**: Thorium (Performance-optimized Chromium).
- **Bridge**: Node.js-based Native Messaging Host.
- **Engine**: Custom headless `aria2c` JSON-RPC server.
- **Management UI**: Flutter-based desktop wrapper for real-time engine control and monitoring.

## 🛠️ Setup & External Binaries
This repository contains the source code, extensions, and orchestration logic. Due to file size limits and the custom nature of the engine, the binaries must be restored separately:

1.  **Download Custom Assets**: Go to the [GitHub Releases](https://github.com/Jack1224E/JBrowser/releases) page.
2.  **Restore Binaries**: Download the custom `aria2c` engine and the Thorium AppImage and place them in the `bin/` directory.
3.  **Run Setup**:
    ```bash
    ./scripts/setup_vault.sh
    ```

## 🚀 Usage
1. Execute the orchestrator script:
    ```bash
    ./scripts/run-pir-browser.sh
    ```
2. The browser will launch with all extensions and engine hooks pre-configured.

---
*Note: This project is dedicated strictly to technical efficiency, engine orchestration, and performance optimization.*
