#!/usr/bin/env bash
# Pallet OS — transform a fresh Ubuntu 24.04 install into a managed Chromebook desktop
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root:"
  echo "  sudo PALLET_SERVER_URL=https://api.example.com PALLET_ENROLLMENT_TOKEN=plt_... $0"
  exit 1
fi

PALLET_USER="${PALLET_USER:-pallet}"
PALLET_SERVER_URL="${PALLET_SERVER_URL:-}"
PALLET_ENROLLMENT_TOKEN="${PALLET_ENROLLMENT_TOKEN:-}"
INSTALL_DIR="${INSTALL_DIR:-/opt/pallet}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Optional: read enrollment vars from a root-only file
if [[ -f /etc/pallet/enroll.env ]]; then
  # shellcheck disable=SC1091
  source /etc/pallet/enroll.env
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server) PALLET_SERVER_URL="$2"; shift 2 ;;
    --token) PALLET_ENROLLMENT_TOKEN="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if findmnt -no fstype / 2>/dev/null | grep -qE 'overlay|squashfs'; then
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║  WARNING: Ubuntu LIVE session detected (Try Ubuntu).           ║"
  echo "║  This install will NOT persist to your internal disk.          ║"
  echo "║                                                                ║"
  echo "║  Instead: choose 'Install Ubuntu' to your internal drive,      ║"
  echo "║  reboot into the installed system, then run this script again.  ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  read -r -p "Continue anyway on live USB? [y/N] " ans
  [[ "${ans,,}" == "y" ]] || exit 1
fi

echo "==> Pallet OS provisioner (Ubuntu 24.04+ / Chromebook)"
echo "    User: $PALLET_USER"
if [[ -n "$PALLET_SERVER_URL" ]]; then
  echo "    Server: $PALLET_SERVER_URL"
else
  echo "    Server: <not set — enroll manually after install>"
fi

export DEBIAN_FRONTEND=noninteractive

echo "==> Installing base packages"
apt-get update
apt-get install -y \
  chromium-browser chromium-codecs-ffmpeg \
  epiphany-browser firefox \
  labwc seatd swayidle swaylock \
  network-manager \
  pipewire wireplumber \
  xwayland \
  curl ca-certificates jq unzip \
  unattended-upgrades apt-listchanges \
  policykit-1 \
  fonts-roboto fonts-noto-color-emoji \
  mesa-utils \
  golang-go nodejs npm \
  linux-modules-extra-$(uname -r) || true

echo "==> Chromebook hardware support"
# Most x86_64 Chromebooks with MrChromebox firmware use standard Ubuntu kernels.
# Additional touchpad/audio firmware may be required per model — see docs/CHROMEBOOK.md
if [[ -f "$SCRIPT_DIR/chromebook-modules.sh" ]]; then
  bash "$SCRIPT_DIR/chromebook-modules.sh" || true
fi

echo "==> Creating managed user"
PALLET_GROUPS="video,input,render,audio"
if getent group waydroid >/dev/null; then
  PALLET_GROUPS="$PALLET_GROUPS,waydroid"
fi
if ! id "$PALLET_USER" &>/dev/null; then
  useradd -m -s /bin/bash -G "$PALLET_GROUPS" "$PALLET_USER"
else
  usermod -aG "$PALLET_GROUPS" "$PALLET_USER" 2>/dev/null || true
fi
echo "$PALLET_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl reboot, /usr/bin/systemctl poweroff" > "/etc/sudoers.d/pallet"
chmod 440 "/etc/sudoers.d/pallet"

echo "==> Unattended security updates"
cat > /etc/apt/apt.conf.d/50pallet-unattended <<'EOF'
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
dpkg-reconfigure -plow unattended-upgrades || true

echo "==> WiFi auto-connect on boot"
bash "$SCRIPT_DIR/network-wifi.sh"

echo "==> Building & installing pallet-shell"
bash "$SCRIPT_DIR/build-shell.sh"
install -m 0755 "$REPO_ROOT/dist/pallet-shell" /usr/local/bin/pallet-shell
install -m 0755 "$SCRIPT_DIR/pallet-shell-launch.sh" /usr/local/bin/pallet-shell-launch
install -m 0755 "$SCRIPT_DIR/pallet-session.sh" /usr/local/bin/pallet-session
install -m 0755 "$SCRIPT_DIR/pallet-lock" /usr/local/bin/pallet-lock

echo "==> Building & installing pallet-agent"
bash "$SCRIPT_DIR/build-agent.sh"
install -m 0755 "$REPO_ROOT/dist/pallet-agent" /usr/local/bin/pallet-agent
mkdir -p /var/lib/pallet
cat > /var/lib/pallet/versions.json <<EOF
{
  "agent": "1.0.0",
  "shell": "1.0.0"
}
EOF
mkdir -p /etc/pallet /var/lib/pallet
chmod 700 /etc/pallet

if [[ -f /etc/pallet/agent.json ]]; then
  if [[ -n "$PALLET_SERVER_URL" ]]; then
    echo "==> Updating server URL in existing agent config (keeping enrollment)"
    tmp="$(mktemp)"
    jq --arg url "$PALLET_SERVER_URL" '.server_url = $url' /etc/pallet/agent.json >"$tmp"
    install -m 0600 "$tmp" /etc/pallet/agent.json
    rm -f "$tmp"
  fi
elif [[ -n "$PALLET_SERVER_URL" ]]; then
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

echo "==> Desktop session logging"
mkdir -p /var/log/pallet
chown "$PALLET_USER:$PALLET_USER" /var/log/pallet
chmod 755 /var/log/pallet

echo "==> Browser permissions for greetd Wayland session"
if command -v snap >/dev/null; then
  if snap list chromium &>/dev/null; then
    snap connect chromium:wayland 2>/dev/null || true
    snap connect chromium:network 2>/dev/null || true
    snap connect chromium:home 2>/dev/null || true
    snap connect chromium:audio-playback 2>/dev/null || true
  fi
  if snap list firefox &>/dev/null; then
    snap connect firefox:wayland 2>/dev/null || true
    snap connect firefox:network 2>/dev/null || true
    snap connect firefox:home 2>/dev/null || true
  fi
fi

echo "==> Autologin via greetd (replace Ubuntu GDM)"
# Ubuntu Desktop ships GDM3 as display-manager; greetd conflicts unless removed first.
for dm in gdm3 gdm sddm lightdm; do
  systemctl stop "$dm" 2>/dev/null || true
  systemctl disable "$dm" 2>/dev/null || true
done
if [[ -e /etc/systemd/system/display-manager.service ]]; then
  rm -f /etc/systemd/system/display-manager.service
fi
DEBIAN_FRONTEND=noninteractive apt-get install -y greetd seatd
install -m 0644 "$SCRIPT_DIR/greetd/config.toml" /etc/greetd/config.toml
systemctl daemon-reload
systemctl enable --now seatd
systemctl enable greetd
ln -sf /lib/systemd/system/greetd.service /etc/systemd/system/display-manager.service
usermod -aG seat,video,input,render,audio "$PALLET_USER" 2>/dev/null || true
# pallet-shell is started by labwc rc.xml — systemd unit conflicts with greetd session
systemctl disable pallet-shell 2>/dev/null || true

echo "==> Waydroid (Android apps)"
if [[ -f "$SCRIPT_DIR/install-waydroid.sh" ]]; then
  bash "$SCRIPT_DIR/install-waydroid.sh" || echo "Waydroid install skipped or failed — see docs"
  if getent group waydroid >/dev/null; then
    usermod -aG waydroid "$PALLET_USER" 2>/dev/null || true
  fi
fi

echo "==> Lockdown: hide terminal for managed user"
cat > /etc/pallet/lockdown.conf <<'EOF'
SHOW_TERMINAL=0
SHOW_FILE_MANAGER=0
EOF

echo "==> Disable unused services"
for svc in cups bluetooth avahi-daemon gdm3 gdm; do
  systemctl disable --now "$svc" 2>/dev/null || true
done

systemctl daemon-reload
systemctl enable pallet-agent
systemctl disable pallet-shell 2>/dev/null || true

is_enrolled() {
  [[ -f /etc/pallet/agent.json ]] && \
    jq -e '.device_id != "" and .device_token != ""' /etc/pallet/agent.json >/dev/null 2>&1
}

if [[ -n "$PALLET_ENROLLMENT_TOKEN" && -n "$PALLET_SERVER_URL" ]]; then
  if is_enrolled; then
    echo "==> Device already enrolled — skipping re-enrollment"
    systemctl enable --now pallet-agent || true
  else
    echo "==> Enrolling device"
    pallet-agent -server "$PALLET_SERVER_URL" -enroll "$PALLET_ENROLLMENT_TOKEN" -enroll-only -config /etc/pallet/agent.json
    systemctl enable --now pallet-agent || true
  fi
elif is_enrolled; then
  echo "==> Device already enrolled — restarting agent"
  systemctl enable --now pallet-agent || true
else
  echo ""
  echo "==> Enrollment skipped (server or token not set)"
  echo "    After reboot, run:"
  echo "    sudo PALLET_SERVER_URL=https://your-api.workers.dev \\"
  echo "         PALLET_ENROLLMENT_TOKEN=plt_... \\"
  echo "         $SCRIPT_DIR/enroll-device.sh"
fi

echo ""
echo "Pallet OS provision complete."
echo "Reboot to start the desktop: sudo reboot"
