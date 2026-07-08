#!/usr/bin/env bash
# Chromebook graphics: firmware, Intel i915 quirks, software-rendering fallback.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Chromebook graphics support"

if lspci 2>/dev/null | grep -qiE 'vga|display.*amd'; then
  echo "    Detected AMD GPU"
  apt-get install -y firmware-amd-graphics mesa-vulkan-drivers libgl1-mesa-dri libegl1-mesa-dri mesa-utils 2>/dev/null || true
  install -m 0644 /dev/stdin /etc/modules-load.d/pallet-amdgpu.conf <<'EOF'
amdgpu
EOF
  install -m 0644 /dev/stdin /etc/modprobe.d/pallet-amdgpu.conf <<'EOF'
# Load AMD GPU for KMS/DRM on Chromebooks. Do NOT set amdgpu.dpm=0 (causes black screen).
options amdgpu dc=1
EOF
elif lspci 2>/dev/null | grep -qiE 'vga|display.*intel'; then
  echo "    Detected Intel GPU"
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
  install -m 0644 "$SCRIPT_DIR/drm/i915.conf" /etc/modprobe.d/pallet-i915.conf
  if [[ -f /etc/default/grub ]] && ! grep -q 'i915.enable_guc=0' /etc/default/grub; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="i915.enable_guc=0 i915.enable_psr=0 /' /etc/default/grub
    if command -v update-grub >/dev/null; then
      update-grub || true
    fi
  fi
else
  apt-get install -y linux-firmware mesa-utils libegl1-mesa-dri libgl1-mesa-dri 2>/dev/null || true
fi

KVER="$(uname -r)"
apt-get install -y "linux-modules-extra-${KVER}" 2>/dev/null || true

install -m 0755 "$SCRIPT_DIR/pallet-graphics-env.sh" /usr/local/bin/pallet-graphics-env

update-initramfs -u 2>/dev/null || true
echo "    GPU diagnostics: dmesg | grep -iE 'amdgpu|i915|drm|gpu|firmware'"
echo "    Force software desktop: sudo touch /etc/pallet/force-software-rendering && sudo reboot"
