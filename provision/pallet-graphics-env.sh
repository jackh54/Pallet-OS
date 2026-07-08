#!/usr/bin/env bash
# Source from Pallet desktop session scripts. Falls back to CPU rendering when GPU is broken.

enable_software_rendering() {
  export WLR_RENDERER=pixman
  export LIBGL_ALWAYS_SOFTWARE=1
  export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
  export PALLET_SOFTWARE_RENDERING=1
}

if [[ -f /etc/pallet/force-software-rendering ]]; then
  enable_software_rendering
  return 0 2>/dev/null || exit 0
fi

# greetd does not provide a logind session — use seatd for DRM access.
export LIBSEAT_BACKEND=seatd

if [[ ! -e /dev/dri/card0 ]]; then
  enable_software_rendering
  return 0 2>/dev/null || exit 0
fi

# If the session user cannot open DRM, labwc EGL fails (see session.log).
if ! (command -v sg >/dev/null && sg render -c "test -r /dev/dri/card0" 2>/dev/null) \
  && ! test -r /dev/dri/card0 2>/dev/null; then
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
