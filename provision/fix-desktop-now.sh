#!/usr/bin/env bash
# Install or refresh all Pallet desktop scripts without a full re-provision.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PALLET_USER="${PALLET_USER:-pallet}"

echo "==> Installing Pallet desktop scripts"
for script in pallet-session.sh pallet-drm-setup.sh pallet-x11-session.sh \
  pallet-x11-display.sh pallet-shell-launch.sh pallet-graphics-env.sh pallet-lock; do
  install -m 0755 "$SCRIPT_DIR/$script" "/usr/local/bin/${script%.sh}"
done

echo "==> X11 + browsers + display tools"
export DEBIAN_FRONTEND=noninteractive
apt-get install -y \
  xserver-xorg-core xinit x11-xserver-utils xserver-xorg-video-all \
  xserver-xorg-video-amdgpu xserver-xorg-legacy \
  epiphany-browser firefox \
  2>/dev/null || true
apt-get install -y \
  xserver-xorg-core xinit x11-xserver-utils xserver-xorg-video-all \
  xserver-xorg-video-amdgpu epiphany-browser \
  2>/dev/null || true

# Remove any broken Xorg snippets from earlier releases (invalid Modes "auto" etc.)
rm -f /etc/X11/xorg.conf.d/20-amdgpu.conf.dpkg-bak 2>/dev/null || true

install -m 0644 "$SCRIPT_DIR/xorg/Xwrapper.config" /etc/X11/Xwrapper.config
mkdir -p /etc/X11/xorg.conf.d
install -m 0644 "$SCRIPT_DIR/xorg/20-amdgpu.conf" /etc/X11/xorg.conf.d/20-amdgpu.conf

bash "$SCRIPT_DIR/greetd-seat.sh" || true
bash "$SCRIPT_DIR/chromebook-graphics.sh" || true

install -m 0644 "$SCRIPT_DIR/greetd/config.toml" /etc/greetd/config.toml

mkdir -p /home/$PALLET_USER/.config/labwc /var/log/pallet /etc/pallet
install -m 0644 "$SCRIPT_DIR/labwc/rc.xml" /home/$PALLET_USER/.config/labwc/rc.xml
chown -R "$PALLET_USER:$PALLET_USER" /home/$PALLET_USER/.config
chown "$PALLET_USER:$PALLET_USER" /var/log/pallet

install -m 0755 /dev/stdin "/home/$PALLET_USER/.xinitrc" <<'EOF'
#!/bin/sh
exec /usr/local/bin/pallet-x11-session
EOF
chown "$PALLET_USER:$PALLET_USER" "/home/$PALLET_USER/.xinitrc"

if lspci -nn 2>/dev/null | grep -qiE 'vga|display.*\[(1002|1022):'; then
  echo "amd-x11" > /etc/pallet/desktop-mode
  touch /etc/pallet/force-software-rendering
  echo "    AMD Chromebook: using X11 desktop (skipping labwc)"
fi

echo "==> Verify installed desktop files"
missing=0
for bin in pallet-session pallet-drm-setup pallet-x11-session pallet-x11-display pallet-shell-launch pallet-graphics-env; do
  if [[ -x "/usr/local/bin/$bin" ]]; then
    echo "    OK /usr/local/bin/$bin"
  else
    echo "    MISSING /usr/local/bin/$bin"
    missing=1
  fi
done

if command -v snap >/dev/null && snap list chromium &>/dev/null; then
  snap connect chromium:x11 2>/dev/null || true
  snap connect chromium:network 2>/dev/null || true
  snap connect chromium:home 2>/dev/null || true
  snap connect chromium:audio-playback 2>/dev/null || true
fi

systemctl enable --now seatd greetd 2>/dev/null || true
systemctl restart greetd 2>/dev/null || true

if [[ "$missing" -ne 0 ]]; then
  echo "ERROR: desktop install incomplete"
  exit 1
fi

echo ""
echo "Desktop fix installed. Reboot: sudo reboot"
