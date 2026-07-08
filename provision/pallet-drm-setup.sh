#!/usr/bin/env bash
# Load GPU modules and wait for /dev/dri/card* before starting labwc.
set -euo pipefail

LOG_DIR="/var/log/pallet"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/session.log"

log() {
  echo "$(date -Is) [drm] $*" >>"$LOG"
}

find_drm_card() {
  local card driver path
  for card in /dev/dri/card[0-9]*; do
    [[ -e "$card" ]] || continue
    path="/sys/class/drm/${card##*/}/device/driver"
    driver="$(basename "$(readlink -f "$path" 2>/dev/null || echo "")" 2>/dev/null || true)"
    if [[ "$driver" == "amdgpu" || "$driver" == "i915" || "$driver" == "nouveau" ]]; then
      echo "$card"
      return 0
    fi
  done
  for card in /dev/dri/card[0-9]*; do
    [[ -e "$card" ]] && echo "$card" && return 0
  done
  return 1
}

has_amd_gpu() {
  lspci -nn 2>/dev/null | grep -qiE 'vga|display.*\[(1002|1022):'
}

has_intel_gpu() {
  lspci -nn 2>/dev/null | grep -qiE 'vga|display.*\[8086:'
}

load_gpu_modules() {
  if has_amd_gpu; then
    log "loading amdgpu"
    modprobe amdgpu 2>>"$LOG" || true
  fi
  if has_intel_gpu; then
    log "loading i915"
    modprobe i915 2>>"$LOG" || true
  fi
}

log "pallet-drm-setup starting"
load_gpu_modules

DRM_CARD=""
for _ in $(seq 1 45); do
  DRM_CARD="$(find_drm_card || true)"
  [[ -n "$DRM_CARD" ]] && break
  sleep 1
done

if [[ -z "$DRM_CARD" ]]; then
  log "ERROR: no /dev/dri/card* found after 45s"
  ls -la /dev/dri >>"$LOG" 2>&1 || true
  lspci -k | grep -iEA3 'vga|display' >>"$LOG" 2>&1 || true
  exit 1
fi

export PALLET_DRM_CARD="$DRM_CARD"
export WLR_DRM_DEVICES="$DRM_CARD"
log "using DRM device $DRM_CARD ($(ls -l "$DRM_CARD" 2>/dev/null || echo unknown))"
