#!/usr/bin/env bash
# X11 fallback when Wayland/DRM cannot start (no /dev/dri/card*).
set -uo pipefail

PORT="${PALLET_SHELL_PORT:-7420}"
URL="http://127.0.0.1:${PORT}"
LOG_DIR="/var/log/pallet"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/desktop.log"

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export DISPLAY="${DISPLAY:-:0}"

log() {
  echo "$(date -Is) [x11] $*" >>"$LOG"
}

log "starting X11 fallback session on $DISPLAY"

xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true

/usr/local/bin/pallet-shell >>"$LOG" 2>&1 &
for _ in $(seq 1 60); do
  curl -sf "$URL/api/config" >/dev/null 2>&1 && break
  sleep 0.25
done

for bin in epiphany epiphany-browser firefox chromium chromium-browser; do
  if command -v "$bin" >/dev/null 2>&1; then
    log "launching $bin on X11"
    case "$bin" in
      epiphany|epiphany-browser)
        exec "$bin" --application-mode --profile="${HOME}/.config/pallet-epiphany-x11" "$URL"
        ;;
      firefox)
        exec firefox --kiosk "$URL"
        ;;
      *)
        exec "$bin" --ozone-platform=x11 --kiosk --app="$URL" --no-first-run --disable-gpu
        ;;
    esac
  fi
done

log "ERROR: no browser found for X11 fallback"
exit 1
