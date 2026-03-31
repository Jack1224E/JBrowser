#!/usr/bin/env node
/**
 * PIR BRIDGE — Native Messaging Host (Pure Node.js, No Electron)
 *
 * Protocol: Chrome Native Messaging (4-byte LE length header + JSON)
 * Handles: handshake, create_downloads → logs URLs to bridge_test_log.txt
 */

const fs = require('fs');

const ARIA2_RPC = 'http://127.0.0.1:6800/jsonrpc';

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

function handleMessage(msg) {
    if (msg.type === 'handshake') {
        process.stderr.write('[PirHost] Handshake received. Replying OK.\n');
        sendMessage({ id: msg.id, result: 'ok' });
        return;
    }

    if (msg.type === 'create_downloads' && msg.create_downloads) {
        const downloads = msg.create_downloads.downloads || [];
        process.stderr.write('[PirHost] Received ' + downloads.length + ' download(s). Logging URLs.\n');

        for (const dl of downloads) {
            const url = dl.url || dl.originalUrl;
            if (url) {
                // Log URL to bridge_test_log.txt
                fs.appendFile('/home/jack/Documents/JBrowser/bridge_test_log.txt', url + '\n', (err) => {
                    if (err) {
                        process.stderr.write(`[PirHost] Failed to log URL: ${err.message}\n`);
                    }
                });
            }
        }

        // Send immediate response
        sendMessage({ id: msg.id, result: 'ok' });
        return;
    }

    // Generic ack for anything else with an id
    if (msg.id) {
        sendMessage({ id: msg.id, result: 'ok' });
    }
}


process.stderr.write('[PirHost] Native Messaging Host started.\n');
