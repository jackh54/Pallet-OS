#!/usr/bin/env bash
# greetd session entrypoint — sets up env and starts labwc (or X11 fallback).
set -euo pipefail

PALLET_USER="${PALLET_USER:-pallet}"
PALLET_HOME="/home/${PALLET_USER}"
export HOME="$PALLET_HOME"
export USER="$PALLET_USER"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=PalletOS
export MOZ_ENABLE_WAYLAND=1
export GDK_BACKEND=wayland
export LIBSEAT_BACKEND=seatd

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

LOG_DIR="/var/log/pallet"
mkdir -p "$LOG_DIR"
exec >>"$LOG_DIR/session.log" 2>&1
echo "$(date -Is) pallet-session starting (uid=$(id -u), wayland=${WAYLAND_DISPLAY:-unset}, groups=$(id -Gn))"

if /usr/local/bin/pallet-drm-setup; then
  echo "$(date -Is) DRM ready: ${PALLET_DRM_CARD:-unknown}"
  # shellcheck disable=SC1091
  source /usr/local/bin/pallet-graphics-env
  echo "$(date -Is) graphics mode: ${PALLET_SOFTWARE_RENDERING:+software}${PALLET_SOFTWARE_RENDERING:-hardware} seatd=${LIBSEAT_BACKEND:-unset}"
  exec dbus-run-session -- /usr/bin/labwc -c "$PALLET_HOME/.config/labwc/rc.xml"
fi

echo "$(date -Is) DRM unavailable — falling back to X11"
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
unset MOZ_ENABLE_WAYLAND
exec startx /usr/local/bin/pallet-x11-session -- :0 vt1 -keeptty -nolisten tcp
