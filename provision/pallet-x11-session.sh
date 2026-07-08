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
mkdir -p "$XDG_RUNTIME_DIR"

log() {
  echo "$(date -Is) [x11] $*" >>"$LOG"
}

log "X11 session on $DISPLAY (user=$(id -un), home=$HOME)"

xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true
xsetroot -solid "#1a1a2e" 2>/dev/null || true

/usr/local/bin/pallet-x11-display >>"$LOG" 2>&1 || true

if ! pgrep -x pallet-shell >/dev/null 2>&1; then
  log "starting pallet-shell"
  /usr/local/bin/pallet-shell >>"$LOG" 2>&1 &
fi

shell_ready=0
for _ in $(seq 1 80); do
  if curl -sf "$URL/api/config" >/dev/null 2>&1; then
    shell_ready=1
    break
  fi
  sleep 0.25
done
log "pallet-shell ready=$shell_ready url=$URL"

chromium_bins=(
  /usr/bin/chromium
  /usr/bin/chromium-browser
  /snap/bin/chromium
)

launch_chromium() {
  local bin flags=(
    --ozone-platform=x11
    --kiosk
    "--app=$URL"
    --start-maximized
    --start-fullscreen
    --no-first-run
    --noerrdialogs
    --disable-infobars
    --disable-session-crashed-bubble
    --no-sandbox
    --disable-gpu
    --disable-dev-shm-usage
    --disable-translate
    --no-default-browser-check
  )
  for bin in "${chromium_bins[@]}"; do
    if [[ -x "$bin" ]] || command -v "$bin" >/dev/null 2>&1; then
      log "launching $bin"
      "$bin" "${flags[@]}" >>"$LOG" 2>&1
      return $?
    fi
  done
  return 127
}

launch_epiphany() {
  local bin profile="${HOME}/.config/pallet-epiphany-x11"
  mkdir -p "$profile"
  for bin in epiphany epiphany-browser; do
    if command -v "$bin" >/dev/null 2>&1; then
      log "launching $bin"
      "$bin" --application-mode --profile="$profile" "$URL" >>"$LOG" 2>&1
      return $?
    fi
  done
  return 127
}

launch_firefox() {
  if command -v firefox >/dev/null 2>&1; then
    log "launching firefox"
    firefox --kiosk "$URL" >>"$LOG" 2>&1
    return $?
  fi
  return 127
}

while true; do
  if [[ "$shell_ready" -eq 0 ]]; then
    log "waiting for pallet-shell"
    for _ in $(seq 1 40); do
      curl -sf "$URL/api/config" >/dev/null 2>&1 && shell_ready=1 && break
      sleep 0.25
    done
  fi

  launch_chromium && continue
  log "chromium failed with $?"

  launch_epiphany && continue
  log "epiphany failed with $?"

  launch_firefox && continue
  log "firefox failed with $?"

  log "all browsers failed — check $LOG"
  sleep 5
done
