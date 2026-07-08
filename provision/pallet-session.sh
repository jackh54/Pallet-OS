#!/usr/bin/env bash
# greetd session — AMD Chromebooks use X11; Intel tries Wayland then X11.
set -uo pipefail

PALLET_USER="${PALLET_USER:-pallet}"
PALLET_HOME="/home/${PALLET_USER}"
export HOME="$PALLET_HOME"
export USER="$PALLET_USER"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

LOG_DIR="/var/log/pallet"
mkdir -p "$LOG_DIR"
SESSION_LOG="$LOG_DIR/session.log"

log() {
  echo "$(date -Is) [session] $*" >>"$SESSION_LOG"
}

has_amd_gpu() {
  lspci -nn 2>/dev/null | grep -qiE 'vga|display.*\[(1002|1022):'
}

use_amd_x11() {
  [[ -f /etc/pallet/desktop-mode ]] && grep -q '^amd-x11$' /etc/pallet/desktop-mode
}

run_wayland() {
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  export XDG_SESSION_TYPE=wayland
  export XDG_CURRENT_DESKTOP=PalletOS
  export MOZ_ENABLE_WAYLAND=1
  export GDK_BACKEND=wayland
  export LIBSEAT_BACKEND=seatd
  mkdir -p "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"

  if ! /usr/local/bin/pallet-drm-setup >>"$SESSION_LOG" 2>&1; then
    log "DRM setup failed"
    return 1
  fi

  # shellcheck disable=SC1091
  source /usr/local/bin/pallet-graphics-env
  log "starting labwc (software=${PALLET_SOFTWARE_RENDERING:-0}, drm=${PALLET_DRM_CARD:-unset})"
  dbus-run-session -- /usr/bin/labwc -c "$PALLET_HOME/.config/labwc/rc.xml" >>"$SESSION_LOG" 2>&1
  log "labwc exited with $?"
  return 0
}

cleanup_x11() {
  pkill -u "$PALLET_USER" -x Xorg 2>/dev/null || true
  pkill -u "$PALLET_USER" labwc 2>/dev/null || true
  rm -f /tmp/.X0-lock 2>/dev/null || true
  rm -f /tmp/.X11-unix/X0 2>/dev/null || true
}

run_x11() {
  export XDG_SESSION_TYPE=x11
  export GDK_BACKEND=x11
  unset MOZ_ENABLE_WAYLAND

  local x11_cmd="/usr/local/bin/pallet-x11-session"
  if [[ ! -x "$x11_cmd" ]]; then
    log "ERROR: $x11_cmd missing — run: sudo ./provision/fix-desktop-now.sh"
    return 1
  fi

  cleanup_x11
  modprobe amdgpu 2>/dev/null || true

  log "starting X11 via startx (vt1)"
  # dbus is started inside pallet-x11-session; avoid double dbus-run-session here.
  if ! startx "$x11_cmd" -- :0 vt1 -keeptty -nolisten tcp >>"$SESSION_LOG" 2>&1; then
    log "startx failed — retrying without custom xorg snippets"
    mv /etc/X11/xorg.conf.d/20-amdgpu.conf /etc/X11/xorg.conf.d/20-amdgpu.conf.bak 2>/dev/null || true
    startx "$x11_cmd" -- :0 vt1 -keeptty -nolisten tcp >>"$SESSION_LOG" 2>&1 || true
    [[ -f /etc/X11/xorg.conf.d/20-amdgpu.conf.bak ]] && \
      mv /etc/X11/xorg.conf.d/20-amdgpu.conf.bak /etc/X11/xorg.conf.d/20-amdgpu.conf 2>/dev/null || true
  fi
  log "X11 exited with $?"
  cleanup_x11
  return 0
}

exec >>"$SESSION_LOG" 2>&1
log "pallet-session boot (uid=$(id -u), groups=$(id -Gn))"

if has_amd_gpu || use_amd_x11; then
  log "AMD Chromebook — using X11 desktop path"
  while true; do
    run_x11 || true
    log "X11 retry in 5s"
    sleep 5
  done
fi

while true; do
  run_wayland || true
  log "wayland ended, trying X11"
  run_x11 || true
  log "both sessions failed — retry in 5s"
  sleep 5
done
