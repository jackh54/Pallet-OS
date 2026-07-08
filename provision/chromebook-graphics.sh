#!/usr/bin/env bash
# Chromebook graphics: firmware, Intel i915 quirks, software-rendering fallback.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Chromebook graphics support"

apt-get install -y \
  linux-firmware \
  firmware-linux \
  mesa-utils \
  libegl1-mesa-dri \
  libgl1-mesa-dri \
  intel-media-va-driver-non-free 2>/dev/null || \
apt-get install -y \
  linux-firmware \
  firmware-linux \
  mesa-utils \
  libegl1-mesa-dri \
  libgl1-mesa-dri \
  intel-media-va-driver 2>/dev/null || true

KVER="$(uname -r)"
apt-get install -y "linux-modules-extra-${KVER}" 2>/dev/null || true

install -m 0644 "$SCRIPT_DIR/drm/i915.conf" /etc/modprobe.d/pallet-i915.conf
install -m 0755 "$SCRIPT_DIR/pallet-graphics-env.sh" /usr/local/bin/pallet-graphics-env

if [[ -f /etc/default/grub ]] && ! grep -q 'i915.enable_guc=0' /etc/default/grub; then
  sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="i915.enable_guc=0 i915.enable_psr=0 /' /etc/default/grub
  if command -v update-grub >/dev/null; then
    update-grub || true
  fi
fi

update-initramfs -u 2>/dev/null || true
echo "    GPU diagnostics: dmesg | grep -iE 'i915|drm|gpu|firmware'"
echo "    Force software desktop: sudo touch /etc/pallet/force-software-rendering && sudo reboot"
