#!/usr/bin/env bash
# Source from Pallet desktop session scripts. Falls back to CPU rendering when GPU is broken.

if [[ -f /etc/pallet/force-software-rendering ]]; then
  export WLR_RENDERER=pixman
  export LIBGL_ALWAYS_SOFTWARE=1
  export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
  export PALLET_SOFTWARE_RENDERING=1
  return 0 2>/dev/null || exit 0
fi

if [[ ! -e /dev/dri/card0 ]]; then
  export WLR_RENDERER=pixman
  export LIBGL_ALWAYS_SOFTWARE=1
  export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
  export PALLET_SOFTWARE_RENDERING=1
  return 0 2>/dev/null || exit 0
fi

# Kernel/driver failures on Chromebooks often show before a black screen.
if dmesg 2>/dev/null | grep -qiE 'i915.*failed|i915.*error|amdgpu.*failed|amdgpu.*error|drm.*failed|gpu.*hang|firmware: failed'; then
  export WLR_RENDERER=pixman
  export LIBGL_ALWAYS_SOFTWARE=1
  export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
  export PALLET_SOFTWARE_RENDERING=1
fi
