#!/usr/bin/env bash
# Bring up WiFi at boot and wait for a saved network to connect.
set -euo pipefail

LOG_DIR="/var/log/pallet"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/wifi.log"

log() {
  echo "$(date -Is) [wifi] $*" >>"$LOG"
}

log "pallet-wifi-up starting"

rfkill unblock wifi 2>/dev/null || true
rfkill unblock all 2>/dev/null || true

if command -v nmcli >/dev/null 2>&1; then
  nmcli networking on 2>/dev/null || true
  nmcli radio wifi on 2>/dev/null || true

  while IFS= read -r dev; do
    [[ -n "$dev" ]] || continue
    nmcli device set "$dev" managed yes 2>/dev/null || true
    nmcli device connect "$dev" 2>/dev/null || true
  done < <(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2 == "wifi" { print $1 }')

  while IFS= read -r conn; do
    [[ -n "$conn" ]] || continue
    nmcli connection modify "$conn" \
      connection.autoconnect yes \
      connection.autoconnect-priority 100 2>/dev/null || true
  done < <(nmcli -t -f NAME,TYPE connection show | awk -F: '$2 == "802-11-wireless" { print $1 }')
else
  log "nmcli not found"
  exit 0
fi

for i in $(seq 1 90); do
  state="$(nmcli -t -f STATE general 2>/dev/null || echo unknown)"
  if [[ "$state" == "connected" || "$state" == "connected (local only)" ]]; then
    ssid="$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1 == "yes" { print $2; exit }')"
    log "connected (state=$state ssid=${ssid:-unknown})"
    exit 0
  fi
  sleep 1
done

log "no connection after 90s (state=$(nmcli -t -f STATE general 2>/dev/null || echo unknown))"
exit 0
