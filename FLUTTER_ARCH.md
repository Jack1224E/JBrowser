# Flutter Project Architecture: Pir Switchboard

This document provides a technical audit and architectural map of the Flutter native application located in `pir_switchboard/`. The application serves as a native wrapper and management interface for the `aria2c` download engine.

## 🏗️ Core Architecture Overview

The application follows a reactive architecture powered by **Flutter Riverpod**. It is responsible for the lifecycle of the download engine, the real-time monitoring of download tasks, and the user interface for manual control.

---

## 🛠️ Components Mapping

### 1. Process Management (Ignition)
Handles the spawning, monitoring, and termination of the `aria2c` binary.
- **`lib/providers/engine_process_provider.dart`**: 
  - **Logic**: Uses `Process.start` to launch `aria2c` with `--enable-rpc` and `--rpc-listen-port=6800`.
  - **State**: Tracks `EngineStatus` (starting, connected, error, disconnected).
  - **Validation**: Performs a "warm-up" check by attempting socket connections to the RPC port before declaring the engine as "connected".
- **`lib/services/path_resolver.dart`**: (Referenced) Dynamically locates the `aria2c` binary and session files within the JBrowser vault structure.

### 2. Engine Communication (Commanding)
The bridge between the Flutter UI and the `aria2c` RPC server.
- **`lib/engine/pir_engine_client.dart`**:
  - **Protocol**: Implements **JSON-RPC 2.0** over HTTP.
  - **Capabilities**: `addUri`, `pause`, `unpause`, `tellActive`, `tellStatus`, and `getGlobalStat`.
  - **Structure**: A stateless client that encodes Dart maps into JSON payloads for the engine.

### 3. State Management & Monitoring (The Pulse)
Handles real-time data flow from the engine to the UI.
- **`lib/providers/download_list_provider.dart`**:
  - **Automation**: Listens to the `engineProcessProvider`. When the status becomes `connected`, it automatically spawns a background polling mechanism.
  - **State**: Manages an `AsyncValue<List<DownloadStatus>>`, ensuring the UI handles loading/error states gracefully.
- **`lib/engine/polling_isolate.dart`**:
  - **Performance**: Runs the RPC polling logic in a separate **Dart Isolate** to prevent UI jank.
  - **Frequency**: Polls the engine every **1500ms** to fetch active downloads.

### 4. UI Architecture (The Dashboard)
Renders the visual state and captures user input.
- **`lib/main.dart`**:
  - **Entry Point**: Initializes `ProviderScope` and sets the global dark theme (`0xFF141414`).
  - **Page Orchestration**: The `DashboardPage` serves as the primary view. It triggers the engine "Auto-Start" logic on build.
- **`lib/widgets/`**:
  - **`download_tile.dart`**: A reactive widget that renders individual download progress, speed, and status.
  - **`add_url_dialog`**: (Inline in `main.dart`) Handles the input for new magnet links or direct URLs.

---

## 🚦 Application Flow
1. **Launch**: `main.dart` starts -> `DashboardPage` triggers `engineProcessProvider.start()`.
2. **Process**: `EngineProcessNotifier` spawns `aria2c` -> Verifies port 6800 -> Sets status to `connected`.
3. **Monitor**: `DownloadListNotifier` detects `connected` status -> Spawns `polling_isolate.dart`.
4. **Update**: Isolate sends `PollUpdate` messages -> `downloadListProvider` updates state -> `ListView` re-renders with new speeds/progress.

**[SIGNAL: FLUTTER_AUDIT_COMPLETE]**
