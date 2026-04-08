# Persepolis: Architectural Forensic Audit Findings

## Dimension 1: Process Orchestration & Health

### Extraction 1: Defensive Pre-allocation (ENOSPC Prevention)
- **Source**: `persepolis_research` -> `persepolis/scripts/persepolis_lib_prime.py`
- **Contract**: Disk space requirement must be validated and physically reserved via zero-fill buffer before the high-velocity data stream begins.
- **Failure Mode Prevented**: `Disk Full` errors during a multi-gigabyte session causing unrecoverable partial file fragmentation and OS-level write stalls.
- **Trigger**: `createControlFile` and `create_download_file` event.
- **Extracted Logic**:
  ```text
  1. QUERY [Free Disk Space] on target partition
  2. IF [Free Space] >= [Required File Size]:
     a. OPEN [File Path] in "wb" mode
     b. REPEAT until byte_count == file_size:
        i.  CREATE 1MiB Zero-Buffer (b'\0' * 1024^2)
        ii. WRITE buffer to disk
        iii. IF [Status] == "stopped": BREAK AND DELETE
     c. CLOSE File Handle
  3. ELSE:
     a. SIGNAL "Insufficient Space" error
  ```

### Extraction 2: ACPI Sleep Suppression (Stay-Awake Heartbeat)
- **Source**: `persepolis_research` -> `persepolis/scripts/mainwindow.py`
- **Contract**: Programmatic simulation of user activity must be issued to the OS input stack to prevent power management transitions during active egress/ingress.
- **Failure Mode Prevented**: OS-initiated sleep or "Suspension" dropping active TCP sockets and interrupting headless/unattended downloads.
- **Trigger**: Polling Loop (20-second interval).
- **Extracted Logic**:
  ```text
  1. RECORD [Old Cursor Position]
  2. SLEEP 20s
  3. QUERY [New Cursor Position]
  4. IF [New] == [Old]:
     a. SIGNAL "Keep Awake" to GUI Thread
     b. EXECUTE QCursor.setPos([X+10, Y+10]) 
     c. EXECUTE QCursor.setPos([X, Y]) (Return to Origin)
  5. UPDATE [Old] = [Current]
  ```

---

## Dimension 2: The RPC Layer

### Extraction 3: Exponential Backoff Reconnection logic
- **Source**: `persepolis_research` -> `persepolis/scripts/persepolis_lib_prime.py`
- **Contract**: Network requests must implement an escalating retry policy targeting specific transient HTTP status codes.
- **Failure Mode Prevented**: "Cascading Failure" syndrome where frequent network drops lead to immediate task 'Error' states requiring manual user retry.
- **Trigger**: `requests` Exception or HTTP [429, 500, 502, 503, 504].
- **Extracted Logic**:
  ```text
  1. INITIALIZE [Retry Strategy] with:
     a. [total] = max-tries-from-settings
     b. [backoff_factor] = retry-wait-from-settings
     c. [status_forcelist] = [429, 500, 502, 503, 504]
  2. MOUNT HTTPAdapter with Strategy to Requests Session
  3. ON FAILURE: Scale sleep time by [backoff_factor * (2 ** (retry_count - 1))]
  ```

---

## Dimension 3: Queueing & Persistence

### Extraction 4: Fragmented Persistence (The .persepolis Control Ledger)
- **Source**: `persepolis_research` -> `persepolis/scripts/persepolis_lib_prime.py`
- **Contract**: Parallel segment progress must be mirrored to a local JSON-based sidecar file to ensure cold-start resume capability.
- **Failure Mode Prevented**: Loss of segment-level progress on abrupt crash, forcing a full discard of partially downloaded multi-threaded files.
- **Trigger**: Segment completion or Polling tick.
- **Extracted Logic**:
  ```text
  1. MAINTAIN [Metadata Collection]:
     a. List of 64 Parts: [Start-Byte, Downloaded-Size, Status, Retry-Count]
     b. [ETag] and [File-Size]
  2. ON RESUME:
     a. READ "[FileName].persepolis" JSON
     b. IF [ETag] matches OR [FileSize] matches AND [.persepolis] exists:
        i. HYDRATE state: MARK non-complete parts as "pending"
        ii. SEEK file cursor to [Start-Byte + Downloaded-Size]
  ```

---

## Dimension 4: Lifecycle & Shutdown

### Extraction 5: Synchronous Shutdown Sequential Barrier
- **Source**: `persepolis_research` -> `persepolis/scripts/shutdown.py`
- **Contract**: System-level poweroff commands must be blocked until the internal state machine confirms all volatile data is serialized to the DB.
- **Failure Mode Prevented**: "Ghosting" tasks where a download is 99% done but the DB only knows 50% due to an un-flushed cache during shutdown.
- **Trigger**: App `MainWindow.closeEvent` or Scheduled Shutdown.
- **Extracted Logic**:
  ```text
  1. SIGNAL "shutdown_notification" = 1 (GUI Freeze/Prep)
  2. EXECUTE "stopAllDownloads()" (Pause Engine)
  3. BLOCK until [download_sessions_list] IS EMPTY
  4. SIGNAL "shutdown_notification" = 2 (Handshake Complete)
  5. EXECUTE db.closeConnections()
  6. KILL [threadPool] workers
  7. OS_EXEC: [sudo poweroff] (Linux) OR [shutdown -S] (Win)
  ```

---

## Dimension 5: Exactly-Once Task Delivery

### Extraction 6: URL Uniqueness & GID Collision Defense
- **Source**: `persepolis_research` -> `persepolis/scripts/mainwindow.py`
- **Contract**: Task birth must be gated by a primary key lookup (URL) in the persistent ledger to prevent redundant engine load, while operational identity must be decoupled via a unique GID.
- **Failure Mode Prevented**: "Deadlock" or "Collision" where multiple engine threads attempt to write to the same `.persepolis` control file simultaneously even if they target the same network resource.
- **Trigger**: `addLinkButtonPressed` -> `callBack` event.
- **Extracted Logic**:
  ```text
  1. QUERY persepolis_db: searchLinkInAddLinkTable([URL])
  2. IF exists IS True:
     a. PROMPT user: "This link has been added before! Add anyway?"
     b. IF response IS NO: ABORT birth sequence
  3. EXECUTE gidGenerator() to create 16-char HEX string
  4. INITIALIZE download_table_dict with [URL] AND [NEW_GID]
  5. EXECUTE db.insertInDownloadTable([dict])
  ```
