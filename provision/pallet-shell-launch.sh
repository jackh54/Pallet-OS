#!/usr/bin/env bash
# Start pallet-shell and keep a fullscreen browser open on the shelf UI.
set -uo pipefail

PORT="${PALLET_SHELL_PORT:-7420}"
URL="http://127.0.0.1:${PORT}"
SHELL_BIN="${PALLET_SHELL_BIN:-/usr/local/bin/pallet-shell}"
LOG_DIR="/var/log/pallet"
SHELL_PID=""

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/desktop.log"

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export MOZ_ENABLE_WAYLAND=1
export GDK_BACKEND=wayland

# shellcheck disable=SC1091
source /usr/local/bin/pallet-graphics-env 2>/dev/null || true

log() {
  echo "$(date -Is) [desktop] $*" >>"$LOG"
}

wait_for_wayland() {
  local i socket="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
  for i in $(seq 1 60); do
    if [[ -S "$socket" ]]; then
      return 0
    fi
    sleep 0.25
  done
  log "WARNING: wayland socket not found at $socket"
  return 1
}

wait_for_shell_http() {
  local i
  for i in $(seq 1 60); do
    if curl -sf "$URL/api/config" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

ensure_shell() {
  if wait_for_shell_http; then
    return 0
  fi

  if [[ -n "$SHELL_PID" ]] && kill -0 "$SHELL_PID" 2>/dev/null; then
    wait_for_shell_http && return 0
  fi

  log "starting pallet-shell on $URL"
  "$SHELL_BIN" >>"$LOG" 2>&1 &
  SHELL_PID=$!
  disown "$SHELL_PID" 2>/dev/null || true

  if wait_for_shell_http; then
    log "pallet-shell ready (pid=$SHELL_PID)"
    return 0
  fi

  log "ERROR: pallet-shell failed to start on $URL"
  return 1
}

launch_epiphany() {
  local profile="${HOME:-/home/pallet}/.config/pallet-epiphany"
  local bin
  local -a flags=()
  mkdir -p "$profile"
  if [[ -n "${PALLET_SOFTWARE_RENDERING:-}" ]]; then
    flags+=(--disable-gpu --disable-gpu-compositing)
    export WEBKIT_DISABLE_COMPOSITING_MODE=1
  fi
  for bin in epiphany epiphany-browser; do
    if command -v "$bin" >/dev/null 2>&1; then
      log "trying $bin (software=${PALLET_SOFTWARE_RENDERING:-0})"
      "$bin" --application-mode --profile="$profile" "${flags[@]}" "$URL"
      return $?
    fi
  done
  return 127
}

launch_firefox() {
  log "trying firefox (software=${PALLET_SOFTWARE_RENDERING:-0})"
  local -a flags=(--kiosk --private-window --setDefaultBrowser=false)
  if [[ -n "${PALLET_SOFTWARE_RENDERING:-}" ]]; then
    flags+=(--disable-gpu)
  fi
  MOZ_ENABLE_WAYLAND=1 firefox "${flags[@]}" "$URL"
}

launch_chromium() {
  local bin flags=(
    --kiosk
    "--app=$URL"
    --ozone-platform=wayland
    --start-maximized
    --start-fullscreen
    --no-first-run
    --noerrdialogs
    --disable-infobars
    --disable-session-crashed-bubble
    --disable-translate
    --no-default-browser-check
    --no-sandbox
    --disable-gpu-sandbox
  )
  if [[ -n "${PALLET_SOFTWARE_RENDERING:-}" ]]; then
    flags+=(--disable-gpu --disable-gpu-compositing --use-gl=swiftshader)
  fi

  for bin in /usr/bin/chromium /usr/bin/chromium-browser /snap/bin/chromium; do
    if [[ -x "$bin" ]]; then
      log "trying $bin"
      "$bin" "${flags[@]}"
      return $?
    fi
  done
  return 127
}

launch_browser() {
  if command -v epiphany >/dev/null 2>&1 || command -v epiphany-browser >/dev/null 2>&1; then
    launch_epiphany && return 0
    log "epiphany exited with $?"
  fi

  if command -v firefox >/dev/null 2>&1; then
    launch_firefox && return 0
    log "firefox exited with $?"
  fi

  launch_chromium && return 0
  log "chromium exited with $?"
  return 1
}

log "desktop launcher starting (user=$(id -un), home=${HOME:-unset})"
wait_for_wayland || true
sleep 2

while true; do
  if ensure_shell; then
    if launch_browser; then
      log "browser exited cleanly"
    else
      log "browser launch failed"
    fi
  else
    log "shell unavailable, retrying"
  fi
  sleep 3
done
