#!/usr/bin/env python3
"""
Mock Native Messaging Signal Injector for JBrowser Bridge.

Simulates the Chrome extension sending a Native Messaging payload to pir_host.js
without needing to open Thorium. Uses the 4-byte Little-Endian length-prefixed
protocol that Chromium enforces.

Usage:
    python3 scripts/mock_bridge_signal.py | node scripts/pir_host.js

You can also chain a handshake first:
    python3 scripts/mock_bridge_signal.py --handshake | node scripts/pir_host.js
"""

import json
import struct
import sys

def pack_native_message(obj: dict) -> bytes:
    """Pack a dict into Chrome Native Messaging wire format (4-byte LE header + JSON)."""
    payload = json.dumps(obj).encode('utf-8')
    header = struct.pack('<I', len(payload))
    return header + payload

def main():
    messages = []

    # Optional handshake
    if '--handshake' in sys.argv:
        messages.append({
            "type": "handshake",
            "id": "mock-handshake-001"
        })

    # The download signal
    messages.append({
        "type": "create_downloads",
        "id": "mock-download-001",
        "create_downloads": {
            "downloads": [
                {
                    "url": "https://speedtest.tele2.net/10MB.zip",
                    "headers": {
                        "User-Agent": "PirBrowser/1.0 MockInjector"
                    }
                }
            ]
        }
    })

    for msg in messages:
        packed = pack_native_message(msg)
        sys.stdout.buffer.write(packed)
        sys.stdout.buffer.flush()
        sys.stderr.write(f"[MockInjector] Sent: {json.dumps(msg, indent=2)}\n")

if __name__ == '__main__':
    main()
