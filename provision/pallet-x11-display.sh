#!/usr/bin/env bash
# Configure X11 display: auto-detect panel or apply manual settings from settings.json.
set -uo pipefail

LOG_DIR="/var/log/pallet"
LOG="$LOG_DIR/desktop.log"
SETTINGS="/var/lib/pallet/settings.json"
MODE="${1:-apply}"

log() {
  echo "$(date -Is) [display] $*" >>"$LOG"
}

json_get() {
  local key=$1 default=${2:-}
  if [[ ! -f "$SETTINGS" ]] || ! command -v python3 >/dev/null 2>&1; then
    echo "$default"
    return
  fi
  python3 - "$key" "$default" "$SETTINGS" <<'PY'
import json, sys
key, default, path = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path) as f:
        data = json.load(f)
    val = data.get(key, default)
    if isinstance(val, bool):
        print("true" if val else "false")
    elif val is None:
        print(default)
    else:
        print(val)
except Exception:
    print(default)
PY
}

if ! command -v xrandr >/dev/null 2>&1; then
  log "xrandr not installed"
  [[ "$MODE" == "list" ]] && echo '{"outputs":[],"current":{}}'
  exit 0
fi

for _ in $(seq 1 30); do
  xrandr 2>/dev/null | grep -q ' connected\| disconnected' && break
  sleep 0.25
done

list_outputs_json() {
  python3 - <<'PY'
import json, subprocess, re

def parse_xrandr(text):
    outputs = []
    current = {}
    cur = None
    for line in text.splitlines():
        m = re.match(r'^([A-Za-z0-9-]+)\s+(connected|disconnected)(\s+primary)?(.*)$', line)
        if m:
            if cur:
                outputs.append(cur)
            name, state, _, rest = m.group(1), m.group(2), m.group(3), m.group(4)
            mode = ""
            mm = re.search(r'(\d+x\d+)', rest)
            if mm:
                mode = mm.group(1)
            cur = {
                "name": name,
                "connected": state == "connected",
                "primary": "primary" in (m.group(0)),
                "current_mode": mode,
                "modes": [],
            }
            continue
        if cur and re.match(r'^\s+\d+x\d+', line):
            mode = line.strip().split()[0]
            if mode not in cur["modes"]:
                cur["modes"].append(mode)
    if cur:
        outputs.append(cur)
    for o in outputs:
        if o["connected"] and o["current_mode"]:
            current = {
                "output": o["name"],
                "mode": o["current_mode"],
                "scale": 1.0,
            }
            break
    return outputs, current

try:
    text = subprocess.check_output(["xrandr"], text=True, stderr=subprocess.DEVNULL)
except Exception:
    text = ""
outputs, current = parse_xrandr(text)

# Enrich with sysfs modes
import glob, os
for path in glob.glob("/sys/class/drm/card*-*/modes"):
    status = os.path.join(os.path.dirname(path), "status")
    if not os.path.isfile(status):
        continue
    with open(status) as f:
        if f.read().strip() != "connected":
            continue
    name = os.path.basename(os.path.dirname(path)).split("-", 1)[-1]
    modes = [l.strip() for l in open(path) if l.strip()]
    found = False
    for o in outputs:
        if o["name"] == name or name in o["name"] or o["name"] in name:
            for m in modes:
                if m not in o["modes"]:
                    o["modes"].append(m)
            o["connected"] = True
            found = True
    if not found and modes:
        outputs.append({
            "name": name,
            "connected": True,
            "primary": False,
            "current_mode": modes[0],
            "modes": modes,
        })

print(json.dumps({"outputs": outputs, "current": current}))
PY
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
  command -v cvt >/dev/null 2>&1 || return 1
  cvt_line="$(cvt "$width" "$height" 60 2>/dev/null | awk '/Modeline/{print}')"
  [[ -n "$cvt_line" ]] || return 1
  modeline="${cvt_line#Modeline }"
  mode_name="$(awk '{print $1}' <<<"$modeline" | tr -d '"')"
  log "creating mode $mode_name for $output"
  # shellcheck disable=SC2086
  xrandr --newmode $modeline 2>>"$LOG" || return 1
  xrandr --addmode "$output" "$mode_name" 2>>"$LOG" || return 1
  echo "$mode_name"
}

ensure_mode() {
  local output=$1 mode=$2 width height
  if mode_listed "$output" "$mode"; then
    echo "$mode"
    return 0
  fi
  width="${mode%x*}"
  height="${mode#*x}"
  [[ "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ ]] || return 1
  add_mode_from_cvt "$output" "$width" "$height"
}

find_sysfs_panel() {
  local status dir name native
  for status in /sys/class/drm/card*-*/status; do
    [[ -f "$status" ]] || continue
    grep -qx connected "$status" || continue
    dir=$(dirname "$status")
    name=$(basename "$dir")
    name="${name#*-}"
    [[ -f "$dir/modes" ]] || continue
    native=$(head -1 "$dir/modes" 2>/dev/null || true)
    [[ -n "$native" ]] || continue
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
  local want=${1:-} out
  if [[ -n "$want" ]]; then
    out="$(xrandr 2>/dev/null | awk -v w="$want" '$1==w {print $1; exit}')"
    [[ -n "$out" ]] && echo "$out" && return 0
    out="$(xrandr 2>/dev/null | awk -v w="$want" 'index($1,w){print $1; exit}')"
    [[ -n "$out" ]] && echo "$out" && return 0
  fi
  out="$(xrandr 2>/dev/null | awk '/^eDP.* connected/{print $1; exit}')"
  [[ -n "$out" ]] && echo "$out" && return 0
  xrandr 2>/dev/null | awk '/ connected/{print $1; exit}'
}

apply_output_mode() {
  local output=$1 mode=$2 scale=${3:-1.0}
  local applied width height sx sy

  xrandr --output "$output" --auto 2>>"$LOG" || true
  xrandr --output "$output" --primary 2>>"$LOG" || true

  applied="$(ensure_mode "$output" "$mode" 2>/dev/null || true)"
  [[ -z "$applied" ]] && applied="$mode"

  width="${mode%x*}"
  height="${mode#*x}"

  if xrandr --output "$output" --mode "$applied" --pos 0x0 --scale "${scale}x${scale}" 2>>"$LOG"; then
    if [[ "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ ]]; then
      xrandr --fb "${width}x${height}" 2>>"$LOG" || true
    fi
    log "applied $output mode=$applied scale=$scale"
    return 0
  fi

  if xrandr --output "$output" --auto --scale "${scale}x${scale}" 2>>"$LOG"; then
    log "applied $output --auto scale=$scale"
    return 0
  fi
  log "failed to apply $output $mode"
  return 1
}

apply_auto() {
  local output="" native_mode="" panel best

  if panel="$(find_sysfs_panel 2>/dev/null)"; then
    output="${panel%%|*}"
    native_mode="${panel##*|}"
    log "auto sysfs: $output $native_mode"
  fi

  [[ -z "$output" ]] && output="$(pick_xrandr_output)"
  [[ -z "$output" ]] && { log "no output found"; return 1; }

  if [[ -n "$native_mode" ]]; then
    apply_output_mode "$output" "$native_mode" 1.0 || true
  else
    best="$(xrandr 2>/dev/null | awk -v out="$output" '
      $0 ~ ("^" out " ") {show=1; next}
      show && /^[[:space:]]+[0-9]+x[0-9]+/ {
        gsub(/^[[:space:]]+/, "", $1); split($1,a,"x");
        if (a[1]*a[2]>max){max=a[1]*a[2];mode=$1}
      }
      show && /^[^ \t]/ {show=0}
      END {print mode}
    ')"
    if [[ -n "$best" ]]; then
      apply_output_mode "$output" "$best" 1.0 || true
    else
      xrandr --output "$output" --primary --auto 2>>"$LOG" || true
    fi
  fi

  # Scale up if framebuffer is still smaller than native panel.
  if [[ -n "$native_mode" ]] && command -v xdpyinfo >/dev/null 2>&1; then
    local cur cw ch nw nh sx sy
    cur="$(xdpyinfo 2>/dev/null | awk '/dimensions:/{print $2}')"
    if [[ -n "$cur" && "$cur" != "$native_mode" ]]; then
      cw="${cur%x*}"; ch="${cur#*x}"
      nw="${native_mode%x*}"; nh="${native_mode#*x}"
      if [[ "$cw" =~ ^[0-9]+$ && "$ch" =~ ^[0-9]+$ && "$nw" =~ ^[0-9]+$ && "$nh" =~ ^[0-9]+$ && "$cw" -gt 0 && "$ch" -gt 0 ]]; then
        sx=$(python3 - <<PY
print(f"{int($nw)/int($cw):.4f}")
PY
)
        sy=$(python3 - <<PY
print(f"{int($nh)/int($ch):.4f}")
PY
)
        log "scaling ${cw}x${ch} -> ${nw}x${nh} (${sx}x${sy})"
        xrandr --output "$output" --scale "${sx}x${sy}" 2>>"$LOG" || true
      fi
    fi
  fi
}

apply_manual() {
  local output mode scale
  output="$(json_get display_output "")"
  mode="$(json_get display_mode "")"
  scale="$(json_get display_scale "1.0")"
  [[ -z "$output" ]] && output="$(pick_xrandr_output)"
  [[ -z "$output" ]] && { log "manual: no output"; return 1; }
  [[ -z "$mode" ]] && mode="$(find_sysfs_panel 2>/dev/null | cut -d'|' -f2)"
  [[ -z "$mode" ]] && { log "manual: no mode"; return 1; }
  log "manual: $output $mode scale=$scale"
  apply_output_mode "$output" "$mode" "$scale"
}

case "$MODE" in
  list)
    list_outputs_json
    exit 0
    ;;
  apply|auto|"")
    log "xrandr before: $(xrandr --current 2>&1 | tr '\n' '; ')"
    if [[ "$(json_get display_auto "true")" == "false" ]]; then
      apply_manual || apply_auto
    else
      apply_auto
    fi
    log "xrandr after: $(xrandr --current 2>&1 | tr '\n' '; ')"
    ;;
  *)
    echo "Usage: $0 [apply|list|auto]" >&2
    exit 2
    ;;
esac
