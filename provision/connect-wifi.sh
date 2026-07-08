#!/usr/bin/env bash
# Save a WiFi network for auto-connect on boot.
set -euo pipefail

SSID="${1:-}"
PASSWORD="${2:-}"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0 SSID [password]"
  exit 1
fi

if [[ -z "$SSID" ]]; then
  echo "Nearby networks:"
  nmcli device wifi rescan 2>/dev/null || true
  nmcli device wifi list
  echo ""
  echo "Usage: sudo $0 SSID [password]"
  exit 1
fi

rfkill unblock wifi 2>/dev/null || true
nmcli radio wifi on
nmcli networking on

if [[ -n "$PASSWORD" ]]; then
  nmcli device wifi connect "$SSID" password "$PASSWORD"
else
  nmcli device wifi connect "$SSID"
fi

CONN="$(nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2 == "802-11-wireless" { print $1; exit }')"
if [[ -z "$CONN" ]]; then
  CONN="$SSID"
fi

nmcli connection modify "$CONN" \
  connection.autoconnect yes \
  connection.autoconnect-priority 100 \
  connection.autoconnect-retries 0

echo "Saved '$CONN' for auto-connect on boot."
nmcli connection show "$CONN" | grep -E 'autoconnect|802-11-wireless.ssid'
