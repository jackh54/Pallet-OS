#!/usr/bin/env bash
# Start pallet-shell (HTTP shelf) and open Chromium fullscreen on Wayland.
set -euo pipefail

PORT="${PALLET_SHELL_PORT:-7420}"
URL="http://127.0.0.1:${PORT}"
LOG_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/pallet"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/shell-launch.log"

log() {
  echo "$(date -Is) $*" >>"$LOG"
}

wait_for_shell() {
  local i
  for i in $(seq 1 50); do
    if curl -sf "$URL/api/config" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

find_chromium() {
  local candidate
  for candidate in chromium chromium-browser google-chrome; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

log "pallet-shell-launch starting (user=$(id -un), wayland=${WAYLAND_DISPLAY:-unset})"

if ! wait_for_shell; then
  log "starting pallet-shell on port $PORT"
  /usr/local/bin/pallet-shell >>"$LOG" 2>&1 &
  disown || true
  if ! wait_for_shell; then
    log "ERROR: pallet-shell did not become ready on $URL"
    exit 1
  fi
fi

CHROMIUM="$(find_chromium)" || {
  log "ERROR: chromium not found in PATH"
  exit 1
}

log "opening shelf UI with $CHROMIUM"

export GDK_BACKEND=wayland
exec "$CHROMIUM" \
  --ozone-platform=wayland \
  --kiosk \
  --app="$URL" \
  --no-first-run \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-translate \
  --no-default-browser-check
