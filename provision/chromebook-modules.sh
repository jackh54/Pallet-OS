#!/usr/bin/env bash
# Chromebook-specific kernel modules and firmware helpers
set -euo pipefail
# Install extra modules package matching running kernel when available
KVER="$(uname -r)"
apt-get install -y "linux-modules-extra-${KVER}" 2>/dev/null || true
# Some Chromebooks need touchpad firmware from chromeos-firmware or distro packages
apt-get install -y firmware-linux-nonfree 2>/dev/null || true
echo "Chromebook module step complete for kernel ${KVER}"
