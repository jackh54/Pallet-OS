#!/usr/bin/env bash
# Set native panel resolution on X11 (fixes undersized desktop on Chromebooks).
set -uo pipefail

LOG_DIR="/var/log/pallet"
LOG="$LOG_DIR/desktop.log"

log() {
  echo "$(date -Is) [display] $*" >>"$LOG"
}

if ! command -v xrandr >/dev/null 2>&1; then
  log "xrandr not installed"
  exit 0
fi

log "configuring display: $(xrandr --current 2>&1 | head -5 | tr '\n' ' ')"

primary_output=""
preferred_mode=""
while read -r line; do
  if [[ "$line" =~ ^([A-Za-z0-9-]+)\ connected ]]; then
    primary_output="${BASH_REMATCH[1]}"
    continue
  fi
  if [[ -n "$primary_output" && "$line" =~ ^[[:space:]]+([0-9]+x[0-9]+).*\* ]]; then
    preferred_mode="${BASH_REMATCH[1]}"
    break
  fi
  if [[ -n "$primary_output" && "$line" =~ ^[[:space:]]+([0-9]+x[0-9]+) ]]; then
    [[ -z "$preferred_mode" ]] && preferred_mode="${BASH_REMATCH[1]}"
  fi
done < <(xrandr 2>/dev/null || true)

if [[ -z "$primary_output" ]]; then
  primary_output="$(xrandr | awk '/ connected/{print $1; exit}')"
fi

if [[ -z "$primary_output" ]]; then
  log "no connected output found"
  exit 0
fi

xrandr --output "$primary_output" --primary --auto 2>>"$LOG" || true

if [[ -n "$preferred_mode" ]]; then
  xrandr --output "$primary_output" --mode "$preferred_mode" 2>>"$LOG" || \
    xrandr --output "$primary_output" --auto 2>>"$LOG" || true
  log "set $primary_output to $preferred_mode"
else
  # Use highest available mode
  best="$(xrandr | awk -v out="$primary_output" '
    $1 == out {show=1; next}
    show && /^[[:space:]]+[0-9]+x[0-9]+/ {
      gsub(/^[[:space:]]+/, "", $1)
      split($1, a, "x")
      if (a[1]*a[2] > max) {max=a[1]*a[2]; mode=$1}
    }
    END {print mode}
  ')"
  if [[ -n "$best" ]]; then
    xrandr --output "$primary_output" --mode "$best" 2>>"$LOG" || true
    log "set $primary_output to best mode $best"
  fi
fi

# Fill any remaining unused desktop area (multi-output safety)
xrandr --auto 2>>"$LOG" || true
