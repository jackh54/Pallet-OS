#!/usr/bin/env bash
# X11 kiosk session — shelf UI in a browser.
set -uo pipefail

PORT="${PALLET_SHELL_PORT:-7420}"
URL="http://127.0.0.1:${PORT}"
LOG_DIR="/var/log/pallet"
LOG="$LOG_DIR/desktop.log"

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
unset MOZ_ENABLE_WAYLAND
mkdir -p "$XDG_RUNTIME_DIR" /var/lib/pallet

# shellcheck disable=SC1091
source /usr/local/bin/pallet-graphics-env 2>/dev/null || true

log() {
  echo "$(date -Is) [x11] $*" >>"$LOG"
}

show_status() {
  local msg=$1
  command -v xmessage >/dev/null 2>&1 && \
    xmessage -center -timeout 10 "$msg" >/dev/null 2>&1 &
}

log "X11 session on $DISPLAY (user=$(id -un), home=$HOME)"
show_status "Pallet OS starting..."

xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true
xsetroot -solid "#1a1a2e" 2>/dev/null || true

if [[ -x /usr/local/bin/pallet-x11-display ]]; then
  /usr/local/bin/pallet-x11-display apply >>"$LOG" 2>&1 || true
  sleep 1
  /usr/local/bin/pallet-x11-display apply >>"$LOG" 2>&1 || true
fi

start_shell() {
  [[ -x /usr/local/bin/pallet-shell ]] || {
    log "ERROR: pallet-shell missing"
    return 1
  }
  pgrep -x pallet-shell >/dev/null 2>&1 && return 0
  log "starting pallet-shell"
  /usr/local/bin/pallet-shell >>"$LOG" 2>&1 &
  disown 2>/dev/null || true
}

shell_ready() {
  curl -sf "$URL/api/config" >/dev/null 2>&1
}

start_shell || true

for _ in $(seq 1 60); do
  shell_ready && break
  sleep 0.25
done

if shell_ready; then
  log "pallet-shell ready $URL"
else
  log "WARNING: pallet-shell not ready — opening browser anyway"
fi

show_status "Launching browser..."

while true; do
  start_shell || true
  if [[ -x /usr/local/bin/pallet-browser-launch ]]; then
    log "pallet-browser-launch $URL"
    if /usr/local/bin/pallet-browser-launch "$URL" >>"$LOG" 2>&1; then
      continue
    fi
    log "pallet-browser-launch failed with $?"
  else
    log "ERROR: pallet-browser-launch missing"
  fi
  show_status "Browser failed — retrying in 5s"
  sleep 5
done
