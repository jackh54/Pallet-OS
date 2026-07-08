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

# KMS/connectors can appear a moment after X starts on AMD Chromebooks.
for _ in $(seq 1 24); do
  if xrandr 2>/dev/null | grep -q ' connected'; then
    break
  fi
  sleep 0.25
done

log "xrandr before: $(xrandr --current 2>&1 | tr '\n' '; ')"

find_panel_from_sysfs() {
  local status dir name native
  for status in /sys/class/drm/card*-*/status; do
    [[ -f "$status" ]] || continue
    grep -qx connected "$status" || continue
    dir=$(dirname "$status")
    name=$(basename "$dir")
    name="${name#*-}" # card1-eDP-1 -> eDP-1
    [[ -f "$dir/modes" ]] || continue
    native=$(head -1 "$dir/modes" 2>/dev/null || true)
    [[ -n "$native" ]] || continue
    # Prefer internal panel connectors.
    if [[ "$name" == eDP* ]]; then
      echo "$name|$native"
      return 0
    fi
  done
  for status in /sys/class/drm/card*-*/status; do
    [[ -f "$status" ]] || continue
    grep -qx connected "$status" || continue
    dir=$(dirname "$status")
    name=$(basename "$dir")
    name="${name#*-}"
    [[ -f "$dir/modes" ]] || continue
    native=$(head -1 "$dir/modes" 2>/dev/null || true)
    [[ -n "$native" ]] || continue
    echo "$name|$native"
    return 0
  done
  return 1
}

pick_xrandr_output() {
  local sysfs_name=${1:-} out
  if [[ -n "$sysfs_name" ]]; then
    out="$(xrandr 2>/dev/null | awk -v want="$sysfs_name" '
      $0 ~ ("^" want " ") {print $1; exit}
    ')"
    [[ -n "$out" ]] && echo "$out" && return 0
    out="$(xrandr 2>/dev/null | awk -v want="$sysfs_name" '
      index($1, want) {print $1; exit}
    ')"
    [[ -n "$out" ]] && echo "$out" && return 0
  fi
  out="$(xrandr 2>/dev/null | awk '/^eDP[^ ]* connected/{print $1; exit}')"
  [[ -n "$out" ]] && echo "$out" && return 0
  xrandr 2>/dev/null | awk '/ connected/{print $1; exit}'
}

mode_listed() {
  local output=$1 mode=$2
  xrandr 2>/dev/null | awk -v out="$output" -v mode="$mode" '
    $0 ~ ("^" out " ") {show=1; next}
    show && $1 == mode {found=1; exit}
    show && /^[^ \t]/ {show=0}
    END {exit !found}
  '
}

add_mode_from_cvt() {
  local output=$1 width=$2 height=$3
  local cvt_line modeline mode_name

  if ! command -v cvt >/dev/null 2>&1; then
    return 1
  fi

  cvt_line="$(cvt "$width" "$height" 60 2>/dev/null | awk '/Modeline/{print}')"
  [[ -n "$cvt_line" ]] || return 1

  modeline="${cvt_line#Modeline }"
  mode_name="$(awk '{print $1}' <<<"$modeline" | tr -d '"')"

  log "creating mode $mode_name for $output (${width}x${height})"
  # shellcheck disable=SC2086
  xrandr --newmode $modeline 2>>"$LOG" || return 1
  xrandr --addmode "$output" "$mode_name" 2>>"$LOG" || return 1
  echo "$mode_name"
}

ensure_mode() {
  local output=$1 mode=$2
  local width height

  if mode_listed "$output" "$mode"; then
    echo "$mode"
    return 0
  fi

  width="${mode%x*}"
  height="${mode#*x}"
  [[ "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ ]] || return 1
  add_mode_from_cvt "$output" "$width" "$height"
}

pick_best_xrandr_mode() {
  local output=$1
  xrandr 2>/dev/null | awk -v out="$output" '
    $0 ~ ("^" out " ") {show=1; next}
    show && /^[[:space:]]+[0-9]+x[0-9]+/ {
      gsub(/^[[:space:]]+/, "", $1)
      split($1, a, "x")
      if (a[1] * a[2] > max) {max = a[1] * a[2]; mode = $1}
    }
    show && /^[^ \t]/ {show=0}
    END {print mode}
  '
}

apply_resolution() {
  local output=$1 mode=$2 applied width height

  # Output may show disconnected until explicitly enabled on AMD Chromebooks.
  xrandr --output "$output" --auto 2>>"$LOG" || true
  xrandr --output "$output" --primary 2>>"$LOG" || true

  applied="$(ensure_mode "$output" "$mode" 2>/dev/null || true)"
  [[ -z "$applied" ]] && applied="$mode"

  width="${mode%x*}"
  height="${mode#*x}"

  if xrandr --output "$output" --mode "$applied" --pos 0x0 2>>"$LOG"; then
    [[ "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ ]] && \
      xrandr --fb "${width}x${height}" 2>>"$LOG" || true
    log "set $output to $applied fb=${width}x${height}"
    return 0
  fi

  if xrandr --output "$output" --auto 2>>"$LOG"; then
    log "set $output to --auto (mode $applied failed)"
    return 0
  fi

  log "failed to set $output to $applied"
  return 1
}

output=""
native_mode=""

if panel="$(find_panel_from_sysfs 2>/dev/null)"; then
  output="${panel%%|*}"
  native_mode="${panel##*|}"
  log "sysfs panel: output=$output mode=$native_mode"
fi

if [[ -z "$output" ]]; then
  output="$(pick_xrandr_output)"
elif ! xrandr 2>/dev/null | grep -q "^${output} "; then
  log "xrandr missing $output — trying fuzzy match"
  output="$(pick_xrandr_output "$output")"
fi

if [[ -z "$output" ]]; then
  log "no connected output found"
  exit 0
fi

if [[ -n "$native_mode" ]]; then
  apply_resolution "$output" "$native_mode" || true
else
  preferred=""
  while read -r line; do
    if [[ "$line" =~ ^([A-Za-z0-9-]+)\ connected ]]; then
      primary_output="${BASH_REMATCH[1]}"
      continue
    fi
    if [[ -n "${primary_output:-}" && "$line" =~ ^[[:space:]]+([0-9]+x[0-9]+).*\* ]]; then
      preferred="${BASH_REMATCH[1]}"
      break
    fi
  done < <(xrandr 2>/dev/null || true)

  if [[ -n "$preferred" ]]; then
    apply_resolution "$output" "$preferred" || true
  else
    best="$(pick_best_xrandr_mode "$output")"
    if [[ -n "$best" ]]; then
      apply_resolution "$output" "$best" || true
    else
      xrandr --output "$output" --primary --auto 2>>"$LOG" || true
      log "fallback --auto on $output"
    fi
  fi
fi

# If the framebuffer is still smaller than the panel, expand it.
if [[ -n "$native_mode" ]] && command -v xdpyinfo >/dev/null 2>&1; then
  current="$(xdpyinfo 2>/dev/null | awk '/dimensions:/{print $2}')"
  if [[ -n "$current" && "$current" != "$native_mode" ]]; then
    log "fb $current != panel $native_mode — retrying"
    sleep 0.5
    apply_resolution "$output" "$native_mode" || true
  fi
fi

log "xrandr after: $(xrandr --current 2>&1 | tr '\n' '; ')"
