#!/usr/bin/env bash
# Pallet OS — transform a fresh Ubuntu 24.04 install into a managed Chromebook desktop
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

PALLET_USER="${PALLET_USER:-pallet}"
PALLET_SERVER_URL="${PALLET_SERVER_URL:-}"
PALLET_ENROLLMENT_TOKEN="${PALLET_ENROLLMENT_TOKEN:-}"
INSTALL_DIR="${INSTALL_DIR:-/opt/pallet}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> Pallet OS provisioner (Ubuntu 24.04+ / Chromebook)"
echo "    User: $PALLET_USER"
echo "    Server: ${PALLET_SERVER_URL:-<not set>}"

export DEBIAN_FRONTEND=noninteractive

echo "==> Installing base packages"
apt-get update
apt-get install -y \
  chromium-browser chromium-codecs-ffmpeg \
  labwc seatd swayidle swaylock \
  network-manager nm-tray \
  pipewire wireplumber \
  xwayland \
  curl ca-certificates jq unzip \
  unattended-upgrades apt-listchanges \
  policykit-1 \
  fonts-roboto fonts-noto-color-emoji \
  mesa-utils \
  linux-modules-extra-$(uname -r) || true

echo "==> Chromebook hardware support"
# Most x86_64 Chromebooks with MrChromebox firmware use standard Ubuntu kernels.
# Additional touchpad/audio firmware may be required per model — see docs/CHROMEBOOK.md
if [[ -f "$SCRIPT_DIR/chromebook-modules.sh" ]]; then
  bash "$SCRIPT_DIR/chromebook-modules.sh" || true
fi

echo "==> Creating managed user"
if ! id "$PALLET_USER" &>/dev/null; then
  useradd -m -s /bin/bash -G video,input,render,audio,waydroid "$PALLET_USER"
fi
echo "$PALLET_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl reboot, /usr/bin/systemctl poweroff" > "/etc/sudoers.d/pallet"
chmod 440 "/etc/sudoers.d/pallet"

echo "==> Unattended security updates"
cat > /etc/apt/apt.conf.d/50pallet-unattended <<'EOF'
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
dpkg-reconfigure -plow unattended-upgrades || true

echo "==> Building & installing pallet-shell"
bash "$SCRIPT_DIR/build-shell.sh"
install -m 0755 "$REPO_ROOT/dist/pallet-shell" /usr/local/bin/pallet-shell
install -m 0755 "$SCRIPT_DIR/pallet-lock" /usr/local/bin/pallet-lock

echo "==> Building & installing pallet-agent"
bash "$SCRIPT_DIR/build-agent.sh"
install -m 0755 "$REPO_ROOT/dist/pallet-agent" /usr/local/bin/pallet-agent
mkdir -p /etc/pallet /var/lib/pallet
chmod 700 /etc/pallet

if [[ -n "$PALLET_SERVER_URL" ]]; then
  cat > /etc/pallet/agent.json <<EOF
{
  "server_url": "$PALLET_SERVER_URL",
  "device_id": "",
  "device_token": "",
  "device_key": ""
}
EOF
  chmod 600 /etc/pallet/agent.json
fi

install -m 0644 "$SCRIPT_DIR/systemd/pallet-agent.service" /etc/systemd/system/pallet-agent.service
install -m 0644 "$SCRIPT_DIR/systemd/pallet-shell.service" /etc/systemd/system/pallet-shell.service
install -m 0644 "$SCRIPT_DIR/systemd/labwc-pallet.desktop" /usr/share/wayland-sessions/labwc-pallet.desktop

mkdir -p /home/$PALLET_USER/.config/labwc
install -m 0644 "$SCRIPT_DIR/labwc/rc.xml" /home/$PALLET_USER/.config/labwc/rc.xml
chown -R "$PALLET_USER:$PALLET_USER" /home/$PALLET_USER/.config

echo "==> Autologin via greetd"
apt-get install -y greetd
install -m 0644 "$SCRIPT_DIR/greetd/config.toml" /etc/greetd/config.toml
systemctl enable greetd

echo "==> Waydroid (Android apps)"
if [[ -f "$SCRIPT_DIR/install-waydroid.sh" ]]; then
  bash "$SCRIPT_DIR/install-waydroid.sh" || echo "Waydroid install skipped or failed — see docs"
fi

echo "==> Lockdown: hide terminal for managed user"
cat > /etc/pallet/lockdown.conf <<'EOF'
SHOW_TERMINAL=0
SHOW_FILE_MANAGER=0
EOF

echo "==> Disable unused services"
for svc in cups bluetooth avahi-daemon; do
  systemctl disable --now "$svc" 2>/dev/null || true
done

systemctl daemon-reload
systemctl enable pallet-agent pallet-shell

if [[ -n "$PALLET_ENROLLMENT_TOKEN" && -n "$PALLET_SERVER_URL" ]]; then
  echo "==> Enrolling device"
  pallet-agent -server "$PALLET_SERVER_URL" -enroll "$PALLET_ENROLLMENT_TOKEN" || true
fi

echo ""
echo "Pallet OS provision complete."
echo "Reboot to start the desktop: sudo reboot"
