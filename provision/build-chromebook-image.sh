#!/usr/bin/env bash
# Build a bootable USB image for Chromebooks (MrChromebox UEFI firmware required)
#
# Flash the published artifact with Balena Etcher, Rufus, or:
#   sudo dd if=pallet-os-chromebook.img of=/dev/sdX bs=4M status=progress && sync
#
# Google's Chromebook Recovery Utility expects ChromeOS recovery images and will NOT
# work on stock firmware. With MrChromebox UEFI, use Balena Etcher (recommended).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${PALLET_BUILD_DIR:-$ROOT/build}"
IMAGE="$BUILD/pallet-os-chromebook.img"
SIZE_MB="${PALLET_IMAGE_SIZE_MB:-4096}"
COMPRESS="${PALLET_COMPRESS:-1}"

echo "==> Building Pallet OS Chromebook USB image (${SIZE_MB}MB)"
mkdir -p "$BUILD"

need() {
  for bin in "$@"; do
    command -v "$bin" >/dev/null || { echo "Missing: $bin"; exit 1; }
  done
}
need debootstrap parted losetup mkfs.vfat mkfs.ext4 rsync grub-install

ROOTFS="$BUILD/rootfs"
rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"

echo "==> debootstrap Ubuntu 24.04 minimal (this takes several minutes)"
debootstrap --arch=amd64 noble "$ROOTFS" http://archive.ubuntu.com/ubuntu

echo "==> Copy Pallet OS into rootfs"
mkdir -p "$ROOTFS/opt/pallet-os"
rsync -a \
  --exclude build \
  --exclude .git \
  --exclude node_modules \
  --exclude dist \
  --exclude .next \
  --exclude .wrangler \
  "$ROOT/" "$ROOTFS/opt/pallet-os/"

cat > "$ROOTFS/opt/pallet-os/first-boot.sh" <<'BOOT'
#!/bin/bash
set -euo pipefail
if [[ -f /var/lib/pallet/first-boot-done ]]; then exit 0; fi
export PALLET_SERVER_URL="${PALLET_SERVER_URL:-}"
export PALLET_ENROLLMENT_TOKEN="${PALLET_ENROLLMENT_TOKEN:-}"
/opt/pallet-os/provision/install-pallet-os.sh
touch /var/lib/pallet/first-boot-done
systemctl disable pallet-first-boot.service || true
BOOT
chmod +x "$ROOTFS/opt/pallet-os/first-boot.sh"

cat > "$ROOTFS/etc/systemd/system/pallet-first-boot.service" <<'EOF'
[Unit]
Description=Pallet OS first boot provision
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/var/lib/pallet/first-boot-done

[Service]
Type=oneshot
Environment=PALLET_SERVER_URL=
Environment=PALLET_ENROLLMENT_TOKEN=
ExecStart=/opt/pallet-os/first-boot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# CI-friendly enable (no dbus inside chroot required)
mkdir -p "$ROOTFS/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/pallet-first-boot.service \
  "$ROOTFS/etc/systemd/system/multi-user.target.wants/pallet-first-boot.service"

echo "==> Create disk image"
rm -f "$IMAGE" "$IMAGE.zst"
dd if=/dev/zero of="$IMAGE" bs=1M count="$SIZE_MB" status=none
parted -s "$IMAGE" mklabel gpt
parted -s "$IMAGE" mkpart EFI fat32 1MiB 513MiB
parted -s "$IMAGE" mkpart root ext4 513MiB 100%
parted -s "$IMAGE" set 1 esp on

LOOP="$(losetup -fP --show "$IMAGE")"
cleanup() {
  mountpoint -q "$BUILD/mnt/boot/efi" 2>/dev/null && umount "$BUILD/mnt/boot/efi" || true
  mountpoint -q "$BUILD/mnt" 2>/dev/null && umount "$BUILD/mnt" || true
  losetup -d "$LOOP" 2>/dev/null || true
}
trap cleanup EXIT

mkfs.vfat -F32 "${LOOP}p1"
mkfs.ext4 -F -L pallet-root "${LOOP}p2"
mkdir -p "$BUILD/mnt"
mount "${LOOP}p2" "$BUILD/mnt"
mkdir -p "$BUILD/mnt/boot/efi"
mount "${LOOP}p1" "$BUILD/mnt/boot/efi"
rsync -a "$ROOTFS/" "$BUILD/mnt/"
mkdir -p "$BUILD/mnt/boot/efi/EFI/BOOT"
grub-install \
  --target=x86_64-efi \
  --efi-directory="$BUILD/mnt/boot/efi" \
  --boot-directory="$BUILD/mnt/boot" \
  --removable \
  --no-nvram
cleanup
trap - EXIT

if [[ "$COMPRESS" == "1" ]]; then
  echo "==> Compressing image (for GitHub Releases — raw .img is too large)"
  need zstd
  zstd -T0 -19 -f "$IMAGE" -o "$IMAGE.zst"
  sha256sum "$IMAGE.zst" > "$IMAGE.zst.sha256"
  ls -lh "$IMAGE" "$IMAGE.zst"
else
  sha256sum "$IMAGE" > "$IMAGE.sha256"
  ls -lh "$IMAGE"
fi

echo ""
echo "Done."
echo "  Raw image:  $IMAGE"
[[ -f "$IMAGE.zst" ]] && echo "  Download:   $IMAGE.zst (+ .sha256)"
echo "Flash with Balena Etcher (extract .zst first, or use raw .img locally)."
