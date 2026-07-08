#!/usr/bin/env bash
# AMD Chromebook audio (acp3x-alc5682-max98357 / Picasso).
# DMIC gpio err=-2 is the internal mic — speakers can still work after UCM fix.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! dmesg 2>/dev/null | grep -qi 'acp3x-alc5682-max98357'; then
  if ! grep -qri 'AMDI5682' /sys/bus/acpi/devices/ 2>/dev/null; then
    echo "    No AMD ACP3x ALC5682 audio detected — skipping"
    exit 0
  fi
fi

echo "==> AMD Chromebook audio (acp3x-alc5682-max98357)"

apt-get install -y alsa-ucm-conf pipewire pipewire-pulse wireplumber 2>/dev/null || true

UCM_BASE="/usr/share/alsa/ucm2/AMD"
UCM_DIR="$UCM_BASE/acp3x-alc5682-max98357"
UCM_CONF="$UCM_DIR/acp3x-alc5682-max98357.conf"

# Kernel truncates the ASoC driver name to acp3xalc5682m98 — symlink UCM profile.
if [[ -d "$UCM_DIR" && ! -e "$UCM_BASE/acp3xalc5682m98" ]]; then
  ln -sf "acp3x-alc5682-max98357" "$UCM_BASE/acp3xalc5682m98"
  echo "    Linked UCM profile acp3xalc5682m98 -> acp3x-alc5682-max98357"
fi

# alsa-ucm 1.2.14 regression: wrong HiFi.conf path breaks speakers.
if [[ -f "$UCM_CONF" ]] && grep -q 'File "/AMD/acp3xalc5682m98/HiFi.conf"' "$UCM_CONF"; then
  sed -i 's|File "/AMD/acp3xalc5682m98/HiFi.conf"|File "HiFi.conf"|' "$UCM_CONF"
  echo "    Patched UCM HiFi.conf path"
fi

echo "    Note: 'DMIC gpio failed err=-2' = internal mic only (safe to ignore)"
echo "    Test audio: wpctl status  OR  speaker-test -c2 -t wav"
