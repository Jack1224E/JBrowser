#!/bin/bash
# JBrowser Native Host Launcher (Production Mode)
# Clean binary pipe — no strace, no stdout pollution.

# Log invocation for debugging (stderr only — stdout is reserved for NativeMessaging)
echo "[$(date)] pir_host_launcher.sh EXECUTED (clean mode)" >> /tmp/pir_bridge_debug.log

# Direct exec — replaces this shell process with node, preserving stdin/stdout pipe
exec node "/home/jack/Documents/JBrowser/scripts/pir_host.js" "$@" 2>> /tmp/pir_bridge_debug.log

