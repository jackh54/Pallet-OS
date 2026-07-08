#!/usr/bin/env bash
# Launch fullscreen browser for Pallet shelf UI on X11.
set -uo pipefail

URL="${1:-http://127.0.0.1:7420}"
LOG="/var/log/pallet/desktop.log"

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export DISPLAY="${DISPLAY:-:0}"
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
export MOZ_DISABLE_WAYLAND=1
unset MOZ_ENABLE_WAYLAND

# shellcheck disable=SC1091
source /usr/local/bin/pallet-graphics-env 2>/dev/null || true

log() {
  echo "$(date -Is) [browser] $*" >>"$LOG"
}

ensure_dbus() {
  if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    return 0
  fi
  if command -v dbus-launch >/dev/null 2>&1; then
    # shellcheck disable=SC1090
    eval "$(dbus-launch --sh-syntax)"
    log "dbus session started"
    return 0
  fi
  log "dbus-launch missing"
  return 1
}

run_with_dbus() {
  if command -v dbus-run-session >/dev/null 2>&1; then
    dbus-run-session -- "$@" >>"$LOG" 2>&1
    return $?
  fi
  ensure_dbus || true
  "$@" >>"$LOG" 2>&1
  return $?
}

maximize_window() {
  if command -v wmctrl >/dev/null 2>&1; then
    for _ in $(seq 1 20); do
      wmctrl -l 2>/dev/null | grep -qi . && break
      sleep 0.25
    done
    wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    wmctrl -r :ACTIVE: -e 0,0,0,-1,-1 2>/dev/null || true
  fi
}

try_epiphany() {
  local profile="${HOME:-/home/pallet}/.config/pallet-epiphany-x11"
  local bin flags=(--application-mode "--profile=$profile")
  mkdir -p "$profile"
  if [[ -n "${PALLET_SOFTWARE_RENDERING:-}" ]]; then
    flags+=(--disable-gpu --disable-gpu-compositing)
    export WEBKIT_DISABLE_COMPOSITING_MODE=1
    export LIBGL_ALWAYS_SOFTWARE=1
  fi
  for bin in epiphany-browser epiphany; do
    command -v "$bin" >/dev/null 2>&1 || continue
    log "try $bin $URL"
    run_with_dbus "$bin" "${flags[@]}" "$URL" &
    local pid=$!
    sleep 2
    kill -0 "$pid" 2>/dev/null || return 1
    maximize_window
    wait "$pid"
    return $?
  done
  return 127
}

try_firefox() {
  command -v firefox >/dev/null 2>&1 || return 127
  local flags=(--kiosk --private-window --setDefaultBrowser=false)
  [[ -n "${PALLET_SOFTWARE_RENDERING:-}" ]] && flags+=(--disable-gpu)
  log "try firefox $URL"
  run_with_dbus firefox "${flags[@]}" "$URL" &
  local pid=$!
  sleep 2
  kill -0 "$pid" 2>/dev/null || return 1
  maximize_window
  wait "$pid"
  return $?
}

try_chromium() {
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
    --disable-translate
    --no-default-browser-check
    --disable-dev-shm-usage
  )
  [[ -n "${PALLET_SOFTWARE_RENDERING:-}" ]] && \
    flags+=(--disable-gpu --disable-gpu-compositing --use-gl=swiftshader)

  if command -v snap >/dev/null 2>&1 && snap list chromium &>/dev/null; then
    log "try snap chromium $URL"
    run_with_dbus snap run chromium "${flags[@]}" &
    local pid=$!
    sleep 3
    kill -0 "$pid" 2>/dev/null || return 1
    maximize_window
    wait "$pid"
    return $?
  fi

  for bin in /usr/bin/chromium /usr/bin/chromium-browser; do
    [[ -x "$bin" ]] || continue
    log "try $bin $URL"
    run_with_dbus "$bin" --no-sandbox "${flags[@]}" &
    local pid=$!
    sleep 3
    kill -0 "$pid" 2>/dev/null || return 1
    maximize_window
    wait "$pid"
    return $?
  done
  return 127
}

try_surf() {
  command -v surf >/dev/null 2>&1 || return 127
  log "try surf $URL"
  run_with_dbus surf -F -S "$URL" &
  local pid=$!
  sleep 1
  kill -0 "$pid" 2>/dev/null || return 1
  wait "$pid"
  return $?
}

try_falkon() {
  command -v falkon >/dev/null 2>&1 || return 127
  log "try falkon $URL"
  run_with_dbus falkon --new-window "$URL" &
  local pid=$!
  sleep 2
  kill -0 "$pid" 2>/dev/null || return 1
  maximize_window
  wait "$pid"
  return $?
}

log "browser launch url=$URL display=$DISPLAY user=$(id -un)"

try_epiphany && exit 0
try_firefox && exit 0
try_falkon && exit 0
try_chromium && exit 0
try_surf && exit 0

log "all browsers failed"
exit 1
