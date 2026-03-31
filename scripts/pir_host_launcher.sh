set -euo pipefail
echo "[$(date)] pir_host_launcher.sh EXECUTED" >> /tmp/pir_bridge_debug.log
exec node "/home/jack/Documents/JBrowser/scripts/pir_host.js" "$@" 2>> /tmp/pir_bridge_debug.log
