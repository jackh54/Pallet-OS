#!/usr/bin/env bash
# Source from Pallet desktop session scripts. Falls back to CPU rendering when GPU is broken.

enable_software_rendering() {
  export WLR_RENDERER=pixman
  export LIBGL_ALWAYS_SOFTWARE=1
  export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
  export PALLET_SOFTWARE_RENDERING=1
}

find_drm_card() {
  local card
  for card in /dev/dri/card[0-9]*; do
    [[ -e "$card" ]] || continue
    echo "$card"
    return 0
  done
  return 1
}

if [[ -f /etc/pallet/force-software-rendering ]]; then
  enable_software_rendering
  return 0 2>/dev/null || exit 0
fi

# greetd does not provide a logind session — use seatd for DRM access.
export LIBSEAT_BACKEND=seatd

DRM_CARD="${PALLET_DRM_CARD:-$(find_drm_card || true)}"
if [[ -z "$DRM_CARD" ]]; then
  enable_software_rendering
  return 0 2>/dev/null || exit 0
fi

export PALLET_DRM_CARD="$DRM_CARD"
export WLR_DRM_DEVICES="${WLR_DRM_DEVICES:-$DRM_CARD}"

# If the session user cannot open DRM, labwc EGL fails (see session.log).
if ! (command -v sg >/dev/null && sg render -c "test -r '$DRM_CARD'" 2>/dev/null) \
  && ! test -r "$DRM_CARD" 2>/dev/null; then
  enable_software_rendering
  return 0 2>/dev/null || exit 0
fi

if [[ ! -S /run/seatd.sock ]]; then
  enable_software_rendering
  return 0 2>/dev/null || exit 0
fi

# Kernel/driver failures on Chromebooks often show before a black screen.
if dmesg 2>/dev/null | grep -qiE 'i915.*failed|i915.*error|amdgpu.*failed|amdgpu.*error|drm.*failed|gpu.*hang|firmware: failed'; then
  enable_software_rendering
fi
