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
mkdir -p "$XDG_RUNTIME_DIR"

# shellcheck disable=SC1091
source /usr/local/bin/pallet-graphics-env 2>/dev/null || true

log() {
  echo "$(date -Is) [x11] $*" >>"$LOG"
}

ensure_dbus() {
  if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    return 0
  fi
  if command -v dbus-launch >/dev/null 2>&1; then
    # shellcheck disable=SC1090
    eval "$(dbus-launch --sh-syntax --exit-with-session)"
    log "started dbus session"
    return 0
  fi
  log "WARNING: dbus-launch missing (install dbus-x11)"
  return 1
}

show_status() {
  local msg=$1
  if command -v xmessage >/dev/null 2>&1; then
    xmessage -center -timeout 8 "$msg" >/dev/null 2>&1 &
  fi
}

maximize_active_window() {
  if command -v wmctrl >/dev/null 2>&1; then
    sleep 1
    wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    wmctrl -r :ACTIVE: -e 0,0,0,-1,-1 2>/dev/null || true
  fi
}

log "X11 session on $DISPLAY (user=$(id -un), home=$HOME, software=${PALLET_SOFTWARE_RENDERING:-0})"
ensure_dbus || true
show_status "Pallet OS starting..."

xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true
xsetroot -solid "#1a1a2e" 2>/dev/null || true

configure_display() {
  if [[ -x /usr/local/bin/pallet-x11-display ]]; then
    /usr/local/bin/pallet-x11-display >>"$LOG" 2>&1 || true
  elif command -v xrandr >/dev/null 2>&1; then
    local out
    out="$(xrandr | awk '/ connected/{print $1; exit}')"
    [[ -n "$out" ]] && xrandr --output "$out" --primary --auto 2>>"$LOG" || true
  fi
}

configure_display
sleep 1
configure_display

start_shell() {
  if [[ ! -x /usr/local/bin/pallet-shell ]]; then
    log "ERROR: /usr/local/bin/pallet-shell missing — run: sudo ./provision/fix-desktop-now.sh"
    return 1
  fi
  if pgrep -x pallet-shell >/dev/null 2>&1; then
    return 0
  fi
  log "starting pallet-shell"
  /usr/local/bin/pallet-shell >>"$LOG" 2>&1 &
  disown 2>/dev/null || true
  return 0
}

shell_http_ready() {
  curl -sf "$URL/api/config" >/dev/null 2>&1
}

start_shell || true

launch_surf() {
  if ! command -v surf >/dev/null 2>&1; then
    return 127
  fi
  log "launching surf $URL"
  surf -F -S "$URL" >>"$LOG" 2>&1
  return $?
}

launch_epiphany() {
  local profile="${HOME:-/home/pallet}/.config/pallet-epiphany-x11"
  local bin
  local -a flags=(--application-mode "--profile=$profile")

  mkdir -p "$profile"
  if [[ -n "${PALLET_SOFTWARE_RENDERING:-}" ]]; then
    flags+=(--disable-gpu --disable-gpu-compositing)
    export WEBKIT_DISABLE_COMPOSITING_MODE=1
  fi

  for bin in epiphany epiphany-browser; do
    if command -v "$bin" >/dev/null 2>&1; then
      log "launching $bin $URL"
      "$bin" "${flags[@]}" "$URL" >>"$LOG" 2>&1 &
      local pid=$!
      maximize_active_window
      wait "$pid"
      return $?
    fi
  done
  return 127
}

launch_firefox() {
  local -a flags=(--kiosk --private-window --setDefaultBrowser=false)
  if [[ -n "${PALLET_SOFTWARE_RENDERING:-}" ]]; then
    flags+=(--disable-gpu)
  fi
  if command -v firefox >/dev/null 2>&1; then
    log "launching firefox $URL"
    firefox "${flags[@]}" "$URL" >>"$LOG" 2>&1 &
    local pid=$!
    maximize_active_window
    wait "$pid"
    return $?
  fi
  return 127
}

launch_chromium() {
  local bin
  local -a flags=(
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

  if [[ -n "${PALLET_SOFTWARE_RENDERING:-}" ]]; then
    flags+=(--disable-gpu --disable-gpu-compositing --use-gl=swiftshader)
  fi

  for bin in /usr/bin/chromium /usr/bin/chromium-browser /snap/bin/chromium; do
    if [[ "$bin" == /snap/bin/chromium ]]; then
      if command -v snap >/dev/null 2>&1 && snap list chromium &>/dev/null; then
        log "launching snap run chromium $URL"
        snap run chromium "${flags[@]}" >>"$LOG" 2>&1 &
        local pid=$!
        maximize_active_window
        wait "$pid"
        return $?
      fi
      continue
    fi
    if [[ -x "$bin" ]] || command -v "$bin" >/dev/null 2>&1; then
      log "launching $bin $URL"
      "$bin" --no-sandbox "${flags[@]}" >>"$LOG" 2>&1 &
      local pid=$!
      maximize_active_window
      wait "$pid"
      return $?
    fi
  done
  return 127
}

log "browsers: surf=$(command -v surf 2>/dev/null || echo missing) epiphany=$(command -v epiphany-browser 2>/dev/null || command -v epiphany 2>/dev/null || echo missing) chromium=$(command -v chromium 2>/dev/null || echo missing) shell=$(command -v pallet-shell 2>/dev/null || echo missing)"

while true; do
  start_shell || true

  if ! shell_http_ready; then
    log "waiting for pallet-shell at $URL"
    show_status "Starting Pallet shell..."
    for _ in $(seq 1 40); do
      shell_http_ready && break
      sleep 0.25
    done
  fi

  if shell_http_ready; then
    log "pallet-shell ready url=$URL"
    show_status "Launching browser..."
  else
    log "WARNING: pallet-shell not ready — launching browser anyway"
    show_status "Shell starting — opening browser..."
  fi

  launch_surf && continue
  log "surf failed with $?"

  launch_epiphany && continue
  log "epiphany failed with $?"

  launch_firefox && continue
  log "firefox failed with $?"

  launch_chromium && continue
  log "chromium failed with $?"

  log "all browsers failed — check $LOG"
  show_status "Browser failed — retrying. See /var/log/pallet/desktop.log"
  sleep 5
done
