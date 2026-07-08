#!/usr/bin/env bash
# Build a bootable USB image for Chromebooks (MrChromebox UEFI firmware required)
#
# Google's Chromebook Recovery Utility writes ChromeOS recovery images.
# Pallet OS ships as a standard UEFI USB installer compatible with Chromebooks
# that have been flashed to Full ROM / UEFI firmware (MrChromebox).
#
# Usage:
#   sudo ./build-chromebook-image.sh
#   # Write build/pallet-os-chromebook.img to USB via:
#   #   sudo dd if=build/pallet-os-chromebook.img of=/dev/sdX bs=4M status=progress
#   # Or use Chromebook Recovery Utility "Use local image" if available in your version.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
IMAGE="$BUILD/pallet-os-chromebook.img"
SIZE_MB=6144

echo "==> Building Pallet OS Chromebook USB image"
mkdir -p "$BUILD"

if ! command -v debootstrap >/dev/null; then
  echo "Install debootstrap: sudo apt install debootstrap grub-efi-amd64-bin"
  exit 1
fi

ROOTFS="$BUILD/rootfs"
rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"

echo "==> debootstrap Ubuntu 24.04 minimal"
debootstrap --arch=amd64 noble "$ROOTFS" http://archive.ubuntu.com/ubuntu

echo "==> Copy Pallet OS into rootfs"
mkdir -p "$ROOTFS/opt/pallet-os"
rsync -a --exclude build --exclude .git "$ROOT/" "$ROOTFS/opt/pallet-os/"

cat > "$ROOTFS/opt/pallet-os/first-boot.sh" <<'BOOT'
#!/bin/bash
set -euo pipefail
if [[ -f /var/lib/pallet/first-boot-done ]]; then exit 0; fi
/opt/pallet-os/provision/install-pallet-os.sh
touch /var/lib/pallet/first-boot-done
systemctl disable pallet-first-boot.service
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

chroot "$ROOTFS" systemctl enable pallet-first-boot.service

echo "==> Create disk image"
rm -f "$IMAGE"
dd if=/dev/zero of="$IMAGE" bs=1M count="$SIZE_MB" status=none
parted -s "$IMAGE" mklabel gpt
parted -s "$IMAGE" mkpart EFI fat32 1MiB 513MiB
parted -s "$IMAGE" set 1 esp on
parted -s "$IMAGE" mkpart root ext4 513MiB 100%
LOOP=$(losetup -fP --show "$IMAGE")
trap 'losetup -d "$LOOP"' EXIT
mkfs.vfat -F32 "${LOOP}p1"
mkfs.ext4 -F "${LOOP}p2"
mkdir -p "$BUILD/mnt"
mount "${LOOP}p2" "$BUILD/mnt"
mkdir -p "$BUILD/mnt/boot/efi"
mount "${LOOP}p1" "$BUILD/mnt/boot/efi"
rsync -a "$ROOTFS/" "$BUILD/mnt/"
mkdir -p "$BUILD/mnt/boot/efi/EFI/BOOT"
grub-install --target=x86_64-efi --efi-directory="$BUILD/mnt/boot/efi" --boot-directory="$BUILD/mnt/boot" --removable
umount "$BUILD/mnt/boot/efi"
umount "$BUILD/mnt"
losetup -d "$LOOP"
trap - EXIT

echo ""
echo "Image ready: $IMAGE"
echo "Flash to USB and boot on UEFI-enabled Chromebooks."
echo "See docs/CHROMEBOOK.md for firmware prerequisites."
