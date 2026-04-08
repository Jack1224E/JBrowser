# Motrix-Next: Architectural Forensic Audit Findings

## Dimension 1: Process Orchestration & Health

### Extraction 1: Stale Instance Reclamation
- **Source**: `motrix_research` -> `src-tauri/src/engine/cleanup.rs`
- **Contract**: The RPC port must be exclusively owned by the current authorized sidecar instance.
- **Failure Mode Prevented**: "Address already in use" binding failures and IPC conflicts between zombie and active engines.
- **Trigger**: `start_engine` or `restart_engine` event.
- **Extracted Logic**: 
  ```text
  1. Validate Port as u16 (Injection Guard)
  2. Query OS for PIDs using [Port] (lsof/netstat)
  3. FOR EACH PID:
     a. Query Process Name (ps/tasklist)
     b. IF Name matches "aria2c" OR "motrixnext-aria2c":
        i.  Execute FORCE_KILL (SIGKILL / taskkill /F)
        ii. MARK "killed_any" = TRUE
  4. IF "killed_any" IS TRUE:
     a. SLEEP 300ms (OS Port Release Buffer)
  ```

### Extraction 2: Cross-Platform Path Normalization
- **Source**: `motrix_research` -> `src-tauri/src/engine/state.rs`
- **Contract**: External sidecar binaries must receive paths in a format compatible with their native runtime (MinGW/MSVC).
- **Failure Mode Prevented**: Sidecar immediate exit (os error 2) when encountering Windows extended-length prefixes (\\?\).
- **Trigger**: Sidecar Spawn configuration.
- **Extracted Logic**:
  ```text
  1. RECEIVE [Absolute Path] from Tauri API
  2. IF OS is "Windows":
     a. STRIP prefix "\\?\" using simplified normalization
     b. CONVERT to Legacy Win32 string
  3. RETURN [Safe String] to Sidecar Spawn Args
  ```

---

## Dimension 2: Cold Start Barrier

### Extraction 3: Autostart Silent Proxy
- **Source**: `motrix_research` -> `src-tauri/src/lib.rs`
- **Contract**: The application must remain visually invisible during OS-automated startup unless manual intervention occurs.
- **Failure Mode Prevented**: Disorientation (Window flashing) and UI state races before engine initialization.
- **Trigger**: App `setup()` entry point with `--autostart` flag.
- **Extracted Logic**:
  ```text
  1. CHECK CLI Args for "--autostart"
  2. READ [autoHideWindow] preference from persistent config
  3. IF both are TRUE:
     a. FORCE_HIDE Main Window (Rust-side, PRE-frontend mount)
     b. SET OS Activation Policy to "Accessory" (Hide Dock Icon)
  4. FLAG "engineInitializing" = TRUE in Frontend Store
  5. UI blocks rendering with "Zen-Mode" or Loading overlay until RPC handshake
  ```

---

## Dimension 3: Exactly-Once Delivery (Idempotency)

### Extraction 4: Three-Source State Hydration (Unified Ledger)
- **Source**: `motrix_research` -> `src/stores/task.ts`
- **Contract**: Task identity and metadata must survive the transition between engine memory and persistent disk storage.
- **Failure Mode Prevented**: Disappearing tasks on engine restart or list truncation due to aria2c's `max-completed-tasks` limit.
- **Trigger**: Polling Loop or Tab Change.
- **Extracted Logic**:
  ```text
  1. FETCH [Active/Waiting] from Engine RPC
  2. FETCH [Stopped/Error] from Engine RPC
  3. FETCH [Historical] from SQLite Persistent DB
  4. UNION all sources into [Master Set]
  5. DEDUPLICATE by [GID] and [infoHash]
  6. MAP [addedAt] birth-timestamp from SQLite metadata to Engine objects
  7. SORT and HYDRATE UI State
  ```

---

## Dimension 4: Lifecycle Persistence (Shutdown)

### Extraction 5: Zero-Latency Session Flush
- **Source**: `motrix_research` -> `src-tauri/src/engine/lifecycle.rs`
- **Contract**: In-flight state must be committed to the sidecar's session file without blocking the host's exit sequence.
- **Failure Mode Prevented**: Corruption of magnet/seeding state or loss of segment progress on app exit.
- **Trigger**: App `Exit` signal.
- **Extracted Logic**:
  ```text
  1. INTERCEPT App "Exit" Event
  2. INITIATE "aria2.saveSession" via raw TCP/HTTP POST
  3. SET TIMEOUT = 500ms (Non-blocking Barrier)
  4. IF SIG_INTENTIONAL:
     a. SIGNAL "engine-stopped"
     b. TERMINATE sidecar process
  5. CLEANUP UPnP Port Mappings (Asynchronous)
  ```

---

## Dimension 5: Optimistic UI

### Extraction 6: Dynamic Heartbeat Scaling
- **Source**: `motrix_research` -> `src/stores/app.ts`
- **Contract**: UI update frequency must inversely correlate with task load to mask IPC/RPC latency.
- **Failure Mode Prevented**: UI "stuttering" during 100+ concurrent downloads or excessive CPU consumption when idle.
- **Trigger**: Polling interval tick.
- **Extracted Logic**:
  ```text
  1. COUNT [Active Tasks]
  2. IF Count > 0:
     a. DECREASE [Interval] (e.g., 1000ms -> 200ms)
     b. ENABLE Tray Speedometer updates
  3. IF Count == 0:
     a. INCREASE [Interval] (e.g., up to 5000ms)
     b. DISABLE Tray Speedometer
  4. EMIT [Stat Update] to mask state transition latency
  ```
