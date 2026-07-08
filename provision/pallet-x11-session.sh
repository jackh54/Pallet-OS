#!/usr/bin/env bash
# X11 kiosk session — shelf UI in a browser.
set -uo pipefail

PORT="${PALLET_SHELL_PORT:-7420}"
URL="http://127.0.0.1:${PORT}"
LOG_DIR="/var/log/pallet"
LOG="$LOG_DIR/desktop.log"

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export DISPLAY="${DISPLAY:-:0}"

log() {
  echo "$(date -Is) [x11] $*" >>"$LOG"
}

log "X11 session on $DISPLAY (user=$(id -un))"

xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true

if ! pgrep -x pallet-shell >/dev/null 2>&1; then
  /usr/local/bin/pallet-shell >>"$LOG" 2>&1 &
fi
for _ in $(seq 1 80); do
  curl -sf "$URL/api/config" >/dev/null 2>&1 && break
  sleep 0.25
done

while true; do
  for bin in epiphany epiphany-browser firefox chromium chromium-browser; do
    if command -v "$bin" >/dev/null 2>&1; then
      log "launching $bin"
      case "$bin" in
        epiphany|epiphany-browser)
          "$bin" --application-mode --profile="${HOME}/.config/pallet-epiphany-x11" "$URL" >>"$LOG" 2>&1
          ;;
        firefox)
          firefox --kiosk "$URL" >>"$LOG" 2>&1
          ;;
        *)
          "$bin" --ozone-platform=x11 --kiosk --app="$URL" --no-first-run --disable-gpu >>"$LOG" 2>&1
          ;;
      esac
      log "$bin exited with $?"
    fi
  done
  log "no browser stayed open, retry in 3s"
  sleep 3
done
