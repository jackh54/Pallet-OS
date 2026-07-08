#!/usr/bin/env bash
# greetd session — keeps retrying Wayland then X11; never drops to a dead console.
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

run_x11() {
  export XDG_SESSION_TYPE=x11
  export GDK_BACKEND=x11
  unset MOZ_ENABLE_WAYLAND

  local x11_cmd="/usr/local/bin/pallet-x11-session"
  if [[ ! -x "$x11_cmd" ]]; then
    log "ERROR: $x11_cmd missing — run: sudo ./provision/fix-desktop-now.sh"
    return 1
  fi

  log "starting X11 via startx"
  startx "$x11_cmd" -- :0 vt1 -keeptty -nolisten tcp >>"$SESSION_LOG" 2>&1
  log "X11 exited with $?"
  return 0
}

exec >>"$SESSION_LOG" 2>&1
log "pallet-session boot (uid=$(id -u), groups=$(id -Gn))"

while true; do
  if run_wayland; then
    log "wayland session ended, trying X11"
  fi
  if run_x11; then
    log "x11 session ended, retrying"
  fi
  log "both sessions failed — retry in 5s"
  sleep 5
done
