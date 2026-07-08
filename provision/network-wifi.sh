#!/usr/bin/env bash
# Configure NetworkManager for WiFi auto-connect on boot.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> WiFi auto-connect"
apt-get install -y network-manager rfkill

install -m 0755 "$SCRIPT_DIR/pallet-wifi-up.sh" /usr/local/bin/pallet-wifi-up
install -m 0755 "$SCRIPT_DIR/connect-wifi.sh" /usr/local/bin/pallet-connect-wifi
install -m 0644 "$SCRIPT_DIR/systemd/pallet-wifi.service" /etc/systemd/system/pallet-wifi.service
install -m 0644 "$SCRIPT_DIR/networkmanager/pallet-wifi.conf" /etc/NetworkManager/conf.d/pallet-wifi.conf

systemctl enable NetworkManager
systemctl enable NetworkManager-wait-online.service
systemctl enable pallet-wifi.service

rfkill unblock wifi 2>/dev/null || true
nmcli networking on 2>/dev/null || true
nmcli radio wifi on 2>/dev/null || true

while IFS= read -r conn; do
  [[ -n "$conn" ]] || continue
  nmcli connection modify "$conn" \
    connection.autoconnect yes \
    connection.autoconnect-priority 100 2>/dev/null || true
done < <(nmcli -t -f NAME,TYPE connection show 2>/dev/null | awk -F: '$2 == "802-11-wireless" { print $1 }')

systemctl restart NetworkManager 2>/dev/null || true

echo "    Connect WiFi once with: sudo pallet-connect-wifi \"YourSSID\" \"password\""
