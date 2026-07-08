#!/usr/bin/env bash
# Install Waydroid with optional GAPPS (Play Store) — legal gray area, see docs/LEGAL.md
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if ! command -v waydroid >/dev/null; then
  curl -s https://repo.waydro.id | gpg --dearmor -o /usr/share/keyrings/waydroid.gpg
  echo "deb [signed-by=/usr/share/keyrings/waydroid.gpg] https://repo.waydro.id/ noble main" > /etc/apt/sources.list.d/waydroid.list
  apt-get update
  apt-get install -y waydroid
fi

# Kernel modules for binder/ashmem (required)
if [[ -f /proc/modules ]] && ! grep -q binder_linux /proc/modules 2>/dev/null; then
  modprobe binder_linux devices="binder,hwbinder,vndbinder" || true
  modprobe ashmem_linux || true
  cat > /etc/modules-load.d/pallet-waydroid.conf <<'EOF'
binder_linux
ashmem_linux
EOF
  cat > /etc/modprobe.d/pallet-waydroid.conf <<'EOF'
options binder_linux devices="binder,hwbinder,vndbinder"
EOF
fi

waydroid init -s GAPPS -f || waydroid init -f
systemctl enable --now waydroid-container || true

echo "Waydroid installed. GAPPS variant enables Play Store (see docs/LEGAL.md)."
