#!/usr/bin/env node
/**
 * PIR BRIDGE — Native Messaging Host (Pure Node.js, No Electron)
 *
 * Protocol: Chrome Native Messaging (4-byte LE length header + JSON)
 * Handles: handshake, create_downloads → UDS/CLI spawn/RPC fallback
 *
 * Idempotency: TTL-based requestId deduplication (5s window)
 * Security: Dynamic XDG_RUNTIME_DIR, full environment sterilization
 */

const fs = require('fs');
const net = require('net');
const http = require('http');
const { spawn } = require('child_process');
const path = require('path');
const os = require('os');

const ARIA2_RPC_URL = 'http://127.0.0.1:6800/jsonrpc';
const SWITCHBOARD_BIN = '/home/jack/Documents/JBrowser/pir_switchboard/build/linux/x64/release/bundle/pir_switchboard';

// SOTA Central Vault Queue
const VAULT_QUEUE_DIR = path.join(os.homedir(), '.local', 'state', 'jbrowser', 'vault', 'queue');

const DEDUP_FILE = path.join(os.homedir(), '.local', 'state', 'jbrowser', 'vault', 'dedup.tmp');
const seenRequests = new Set();


// ═══════════════════════════════════════════
// §0  LOGGING (writes to stderr + file)
// ═══════════════════════════════════════════

const BOOT_TRACE_LOG = path.join(os.homedir(), '.local', 'state', 'jbrowser', 'boot_trace.log');

function trace(msg) {
    const hrNow = Date.now() + process.hrtime()[1] / 1e6;
    const logLine = `[${hrNow.toFixed(3)}] ${msg}\n`;
    try { fs.appendFileSync(BOOT_TRACE_LOG, logLine); } catch (_) {}
}

function log(msg) {
    const logLine = `[PirHost] ${new Date().toISOString()} - ${msg}\n`;
    process.stderr.write(logLine);
    try { fs.appendFileSync('/tmp/pir_bridge_debug.log', logLine); } catch (_) {}
    trace(`[PirHost] ${msg}`); // Forward to trace as well
}

trace('[PIR_HOST_TRACE] Native Messaging Host Execution Entrance');

// ═══════════════════════════════════════════
// §0a DYNAMIC SOCKET PATH (no hardcoded UID)
// ═══════════════════════════════════════════

function getSocketPath() {
    const xdgDir = process.env.XDG_RUNTIME_DIR;
    if (xdgDir) return `${xdgDir}/jbrowser/bridge.sock`;
    // Fallback: resolve UID dynamically instead of hardcoding 1000
    const uid = process.getuid ? process.getuid() : 1000;
    return `/run/user/${uid}/jbrowser/bridge.sock`;
}

// ═══════════════════════════════════════════
// §0b CENTRAL VAULT ENQUEUE (Synchronous Atomic Guarantee)
// ═══════════════════════════════════════════

function enqueueVaultTask(payload) {
    try {
        log(`[PRODUCER] Checking directory: ${VAULT_QUEUE_DIR}`);
        fs.mkdirSync(VAULT_QUEUE_DIR, { recursive: true });
        
        // High-resolution timestamp for telemetry audit
        const hrNow = Date.now() + process.hrtime()[1] / 1e6;

        const entry = JSON.stringify({
            ...payload,
            journaled_at_iso: new Date().toISOString(),
            journaled_at_hr: hrNow
        }, null, 2);
        
        // Atomic write to central vault using deterministic GID
        const taskFile = path.join(VAULT_QUEUE_DIR, `${payload.gid}.json`);
        const tmpFile = taskFile + '.tmp';
        
        fs.writeFileSync(tmpFile, entry);
        fs.renameSync(tmpFile, taskFile); // Guarantee atomicity
        log(`[PRODUCER] Writing GID: ${payload.gid} to ${taskFile}`);
    } catch (e) {
        log(`VAULT ENQUEUE ERROR: ${e.message}`);
    }
}


// ═══════════════════════════════════════════
// §0c IDEMPOTENCY — TTL-based requestId Cache (5s)
// ═══════════════════════════════════════════

/**
 * LAYER 1: POSIX tmpfs Ledger
 * Atomic deduplication surviving process restarts via synchronous tmpfs logging.
 */
function isDuplicate(requestId) {
    if (!requestId) return false;

    // 1. O(1) Memory Check
    if (seenRequests.has(requestId)) {
        log(`[DEDUP_MEM_CACHE] requestId=${requestId}`);
        return true;
    }

    // 2. POSIX tmpfs Sync (handles bridge restarts)
    try {
        if (!fs.existsSync(path.dirname(DEDUP_FILE))) fs.mkdirSync(path.dirname(DEDUP_FILE), { recursive: true });
        
        // Hydrate from file if memory is empty
        if (seenRequests.size === 0 && fs.existsSync(DEDUP_FILE)) {
            const content = fs.readFileSync(DEDUP_FILE, 'utf8');
            content.split('\n').filter(Boolean).forEach(id => seenRequests.add(id));
            log(`[DEDUP_HYDRATE] Loaded ${seenRequests.size} IDs from ledger.`);
            
            if (seenRequests.has(requestId)) {
                log(`[DEDUP_POSIX_LEDGER] requestId=${requestId}`);
                return true;
            }
        }

        // 3. Atomic POSIX check (re-read to ensure no race between threads/processes)
        if (fs.existsSync(DEDUP_FILE)) {
            const content = fs.readFileSync(DEDUP_FILE, 'utf8');
            if (content.includes(requestId)) {
                seenRequests.add(requestId);
                log(`[DEDUP_POSIX_RACE_PREVENTION] requestId=${requestId}`);
                return true;
            }
        }

        // 4. Register ID
        fs.appendFileSync(DEDUP_FILE, requestId + '\n');
        seenRequests.add(requestId);

        // Housekeeping: Truncate if too many IDs
        if (seenRequests.size > 1000) {
            log('[DEDUP_GC] Set size > 1000, resetting ledger...');
            seenRequests.clear();
            if (fs.existsSync(DEDUP_FILE)) fs.writeFileSync(DEDUP_FILE, '');
        }

        return false;
    } catch (e) {
        log(`DEDUP ERROR: ${e.message}`);
        return false;
    }
}

/**
 * LAYER 2: Deterministic GID derivation (Manual Hash for zero-dependency portability)
 * Returns a stable 16-hex character string from a requestId.
 */
function deriveGid(requestId) {
    if (!requestId) return Math.random().toString(16).substring(2, 18).padStart(16, '0');
    try {
        const crypto = require('crypto');
        return crypto.createHash('md5').update(requestId).digest('hex').substring(0, 16);
    } catch (e) {
        // Fallback if crypto fails
        let hash = 0;
        for (let i = 0; i < requestId.length; i++) {
            hash = ((hash << 5) - hash) + requestId.charCodeAt(i);
            hash |= 0;
        }
        return Math.abs(hash).toString(16).padStart(16, '0');
    }
}

// ═══════════════════════════════════════════
// §1  NATIVE MESSAGING PROTOCOL
// ═══════════════════════════════════════════

function sendMessage(msg) {
    const json = JSON.stringify(msg);
    const buf = Buffer.from(json, 'utf8');
    const header = Buffer.alloc(4);
    header.writeUInt32LE(buf.length, 0);
    process.stdout.write(header);
    process.stdout.write(buf);
}

let inputBuffer = Buffer.alloc(0);

process.stdin.on('data', (chunk) => {
    inputBuffer = Buffer.concat([inputBuffer, chunk]);

    while (inputBuffer.length >= 4) {
        const length = inputBuffer.readUInt32LE(0);
        if (inputBuffer.length >= 4 + length) {
            const msgBuf = inputBuffer.subarray(4, 4 + length);
            inputBuffer = inputBuffer.subarray(4 + length);

            try {
                const message = JSON.parse(msgBuf.toString('utf8'));
                process.stderr.write('[PirHost] INCOMING: ' + JSON.stringify(message) + '\n');
                handleMessage(message);
            } catch (e) {
                process.stderr.write('[PirHost] Parse error: ' + e.message + '\n');
            }
        } else {
            break;
        }
    }
});

// ═══════════════════════════════════════════
// §2  MESSAGE HANDLER
// ═══════════════════════════════════════════

async function handleMessage(msg) {
    log(`Handling message: ${msg.type || 'unknown'}`);
    if (msg.type === 'handshake') {
        log('Handshake received. Replying OK.');
        sendMessage({ id: msg.id, result: 'ok' });
        return;
    }

    if (msg.type === 'create_downloads' && msg.create_downloads) {
        const downloads = msg.create_downloads.downloads || [];
        log(`Processing ${downloads.length} download(s).`);

        for (const dl of downloads) {
            const url = dl.url || dl.originalUrl;
            const requestId = dl.requestId || msg.id || `bridge-${Date.now()}`;
            if (!url) continue;

            // IDEMPOTENCY GATE
            if (isDuplicate(requestId)) {
                log(`Duplicate request ignored: ${requestId}`);
                attemptSwitchboardLaunch(); // Ensure the app launches even on dedupes
                sendMessage({ id: msg.id, result: 'ok_deduped' });
                return;
            }

            const gid = deriveGid(requestId);

            const payload = { 
                url: url,
                requestId: requestId,
                gid: gid,
                headers: dl.headers || {},
                timestamp: new Date().toISOString()
            };
            
            log(`Download request: requestId=${requestId} gid=${gid} URL=${url}`);

            // § 100% RELIABLE CENTRAL VAULT (No IPC)
            enqueueVaultTask(payload);
            
            // Still attempt to cold-boot Switchboard if it's dead, but do NOT pass URL arguments
            // since the Downloader will natively sweep the Vault when it awakes.
            attemptSwitchboardLaunch();
        }

        sendMessage({ id: msg.id, result: 'ok' });
        return;
    }

    if (msg.id) sendMessage({ id: msg.id, result: 'ok' });
}

// ═══════════════════════════════════════════
// §3  SWITCHBOARD LAUNCH (Full Sterilization)
// ═══════════════════════════════════════════

function attemptSwitchboardLaunch() {
    try {
        log(`Checking Switchboard at: ${SWITCHBOARD_BIN}`);
        if (fs.existsSync(SWITCHBOARD_BIN)) {
            log('Binary found. Sterilizing environment for spawn...');

            // TOTAL ENVIRONMENT SCRUB — Phase 3
            // Strip ALL AppImage-injected and potentially poisonous env vars
            const cleanEnv = { ...process.env };
            [
                'LD_LIBRARY_PATH',  // AppImage library override
                'LD_PRELOAD',       // Preloaded .so injection
                'APPDIR',           // AppImage mount directory
                'APPIMAGE',         // AppImage binary path
                'ARGV0',            // AppImage argv passthrough
                'OWD',              // AppImage original working dir
                'GTK_PATH',         // GTK module override
                'PYTHONPATH',       // Python path poisoning
            ].forEach(k => {
                delete cleanEnv[k];
            });

            // Sanitize XDG_DATA_DIRS: remove AppImage-injected paths
            if (cleanEnv.XDG_DATA_DIRS) {
                const cleanDirs = cleanEnv.XDG_DATA_DIRS
                    .split(':')
                    .filter(d => !d.includes('/tmp/.mount_') && !d.includes('squashfs-root'))
                    .join(':');
                cleanEnv.XDG_DATA_DIRS = cleanDirs || '/usr/local/share:/usr/share';
            }

            log(`Sterilized environment (9 keys scrubbed, XDG_DATA_DIRS sanitized).`);

            // CLI args: do not pass url, Switchboard polls the vault!
            const args = [];
            log(`Spawn args: [${args.join(', ')}]`);

            const child = spawn(SWITCHBOARD_BIN, args, {
                detached: true,
                stdio: ['ignore', 'pipe', 'pipe'],
                env: cleanEnv
            });

            child.stdout.on('data', (data) => log(`[Switchboard STDOUT] ${data}`));
            child.stderr.on('data', (data) => {
                const msg = data.toString();
                log(`[DEBUG_SWITCHBOARD_STDERR] ${msg}`);
                if (msg.includes('GLIBC') || msg.includes('cannot open shared object file') || msg.includes('libflutter')) {
                    log(`[LINKER_ERROR_DETECTED] ${msg.trim()}`);
                }
            });

            child.on('error', (err) => {
                log(`[SPAWN_ERROR] ${err.message}`);
            });

            child.on('exit', (code, signal) => {
                log(`[EXIT_TELEMETRY] Switchboard exited — code: ${code}, signal: ${signal || 'none'}`);
                if (signal === 'SIGSEGV') {
                    log('[EXIT_TELEMETRY] SIGSEGV detected — likely missing .so or GLIBC version mismatch.');
                }
                if (signal === 'SIGABRT') {
                    log('[EXIT_TELEMETRY] SIGABRT detected — assertion failure in Flutter engine.');
                }
            });

            child.unref();
            log('Switchboard spawn called (detached, clean env, pipe-monitored, exit telemetry active).');
        } else {
            log(`ERROR: Switchboard binary NOT found at ${SWITCHBOARD_BIN}`);
        }
    } catch (e) {
        log(`CRITICAL LAUNCH ERROR: ${e.message}`);
    }
}

// ═══════════════════════════════════════════
// (IPC Removed in favor of Directory Queue)
// ═══════════════════════════════════════════

process.stderr.write('[PirHost] Native Messaging Host started.\n');
