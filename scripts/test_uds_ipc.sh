#!/bin/bash
# test_uds_ipc.sh — Send mock payload to Switchboard UDS

SOCKET_PATH="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/jbrowser/bridge.sock"

if [ ! -S "$SOCKET_PATH" ]; then
    # Fallback to /tmp
    SOCKET_PATH="/tmp/jbrowser/bridge.sock"
fi

echo "[Test] Target: $SOCKET_PATH"

if [ ! -S "$SOCKET_PATH" ]; then
    echo "[Error] Socket not found. Is Switchboard running?"
    exit 1
fi

PAYLOAD='{"url": "https://example.com/test_file_uds_optimistic.zip", "headers": {"X-Pir-Test": "1"}}'

# Use Node.js to send the payload (reliable cross-platform)
node -e "
const net = require('net');
const client = net.createConnection('$SOCKET_PATH', () => {
    client.write('$PAYLOAD');
    client.end();
    console.log('[Success] Payload sent to UDS.');
    process.exit(0);
});
client.on('error', (err) => {
    console.error('[Error]', err.message);
    process.exit(1);
});
"
