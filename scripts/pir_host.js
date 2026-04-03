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
const SWITCHBOARD_BIN = '/home/jack/Documents/JBrowser/pir_switchboard/build/linux/x64/debug/bundle/pir_switchboard';
const PENDING_LINKS_DIR = path.join(os.homedir(), '.local', 'state', 'jbrowser');
const PENDING_LINKS_FILE = path.join(PENDING_LINKS_DIR, 'pending_links.jsonl');

// ═══════════════════════════════════════════
// §0  LOGGING (writes to stderr + file)
// ═══════════════════════════════════════════

function log(msg) {
    const logLine = `[PirHost] ${new Date().toISOString()} - ${msg}\n`;
    process.stderr.write(logLine);
    try { fs.appendFileSync('/tmp/pir_bridge_debug.log', logLine); } catch (_) {}
}

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
// §0b DEAD LETTER JOURNAL (Resilient Delivery with Receipts)
// ═══════════════════════════════════════════

function journalLink(payload) {
    try {
        fs.mkdirSync(PENDING_LINKS_DIR, { recursive: true });
        const entry = JSON.stringify({
            ...payload,
            journaled_at: new Date().toISOString(),
            delivered_at: null    // Receipt: null = undelivered
        }) + '\n';
        fs.appendFileSync(PENDING_LINKS_FILE, entry);
        log(`Dead letter journaled: ${payload.url}`);
    } catch (e) {
        log(`JOURNAL ERROR: ${e.message}`);
    }
}

/** Stamp a journal entry as delivered so the Flutter sweep ignores it. */
function markJournalDelivered(requestId) {
    try {
        if (!fs.existsSync(PENDING_LINKS_FILE)) return;
        const lines = fs.readFileSync(PENDING_LINKS_FILE, 'utf8').split('\n').filter(Boolean);
        const updated = lines.map(line => {
            try {
                const entry = JSON.parse(line);
                if (entry.requestId === requestId && !entry.delivered_at) {
                    entry.delivered_at = new Date().toISOString();
                }
                return JSON.stringify(entry);
            } catch (_) { return line; }
        }).join('\n') + '\n';
        fs.writeFileSync(PENDING_LINKS_FILE, updated);
    } catch (e) {
        log(`JOURNAL RECEIPT ERROR: ${e.message}`);
    }
}

// ═══════════════════════════════════════════
// §0c IDEMPOTENCY — TTL-based requestId Cache (5s)
// ═══════════════════════════════════════════

const seenRequests = new Map();
const DEDUP_TTL_MS = 5000;

function isDuplicate(requestId) {
    if (!requestId) return false;
    const now = Date.now();
    if (seenRequests.has(requestId)) {
        log(`DUPLICATE SUPPRESSED (bridge-level): requestId=${requestId}`);
        return true;
    }
    seenRequests.set(requestId, now);
    // Housekeeping: evict expired entries
    for (const [key, ts] of seenRequests) {
        if ((now - ts) > DEDUP_TTL_MS) seenRequests.delete(key);
    }
    return false;
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
                sendMessage({ id: msg.id, result: 'ok_deduped' });
                return;
            }

            const payload = { 
                url: url,
                requestId: requestId,
                headers: dl.headers || {},
                timestamp: new Date().toISOString()
            };
            
            log(`Download request: requestId=${requestId} URL=${url}`);

            // § DEAD LETTER JOURNAL — persist before any IPC attempt
            journalLink(payload);
            
            // ═══════════════════════════════════════════
            // § OPTIMISTIC IPC BRIDGE (UDS)
            // ═══════════════════════════════════════════
            const udsSuccess = await attemptUdsHandoff(payload);
            log(`UDS Handoff result: ${udsSuccess}`);
            
            if (!udsSuccess) {
                log('UDS failed. Attempting Switchboard launch with URL.');
                attemptSwitchboardLaunch(url, requestId);
                
                // Exponential backoff UDS retry loop
                const retrySuccess = await waitForUds(payload, 4000);
                log(`UDS Backoff result: ${retrySuccess}`);

                if (retrySuccess) {
                    markJournalDelivered(requestId);
                } else {
                    log('UDS backoff exhausted. Falling back to HTTP RPC.');
                    const rpcOk = await attemptRpcFallback(url, payload.headers);
                    if (rpcOk) markJournalDelivered(requestId);
                }
            } else {
                markJournalDelivered(requestId);
            }
        }

        sendMessage({ id: msg.id, result: 'ok' });
        return;
    }

    if (msg.id) sendMessage({ id: msg.id, result: 'ok' });
}

// ═══════════════════════════════════════════
// §3  SWITCHBOARD LAUNCH (Full Sterilization)
// ═══════════════════════════════════════════

function attemptSwitchboardLaunch(url, requestId) {
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

            // CLI args: pass URL and requestId for sink-level deduplication
            const args = ['--download-url', url, '--request-id', requestId];
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
// §4  UDS HANDOFF
// ═══════════════════════════════════════════

async function waitForUds(payload, deadlineMs, delay = 200) {
    const start = Date.now();
    const socketPath = getSocketPath();

    async function poll(currentDelay) {
        log(`Polling UDS (backoff): ${currentDelay}ms...`);
        const success = await attemptUdsHandoff(payload);
        if (success) return true;

        if (Date.now() - start >= deadlineMs) {
            log('UDS Poll Deadline Exceeded.');
            return false;
        }

        await new Promise(r => setTimeout(r, currentDelay));
        const nextDelay = Math.min(Math.floor(currentDelay * 1.5), 800);
        return poll(nextDelay);
    }

    return poll(delay);
}

async function attemptUdsHandoff(payload) {
    const socketPath = getSocketPath();
    log(`Attempting UDS connection to: ${socketPath}`);
    return new Promise((resolve) => {
        const client = net.createConnection({ path: socketPath }, () => {
            client.write(JSON.stringify(payload));
            client.end();
            log('Socket handoff successful.');
            resolve(true);
        });

        client.setTimeout(200);
        client.on('timeout', () => {
            client.destroy();
            resolve(false);
        });

        client.on('error', () => {
            resolve(false);
        });
    });
}

// ═══════════════════════════════════════════
// §5  HTTP RPC FALLBACK
// ═══════════════════════════════════════════

function attemptRpcFallback(url, headers) {
    return new Promise((resolve) => {
        const rpcPayload = JSON.stringify({
            jsonrpc: '2.0',
            id: 'pir-fallback-' + Date.now(),
            method: 'aria2.addUri',
            params: [[url], { header: Object.entries(headers).map(([k, v]) => `${k}: ${v}`) }]
        });

        const req = http.request(ARIA2_RPC_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }
        }, (res) => {
            resolve(true);
        });

        req.on('error', (e) => {
            process.stderr.write(`[PirHost] RPC Fallback Failed: ${e.message}\n`);
            resolve(false);
        });

        req.write(rpcPayload);
        req.end();
    });
}


process.stderr.write('[PirHost] Native Messaging Host started.\n');
