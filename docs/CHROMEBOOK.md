# Installing Pallet OS on a real Chromebook

## Important: Chromebook Recovery Utility vs. Linux

Google's **Chromebook Recovery Utility** is designed for **official ChromeOS recovery images**. Pallet OS is a **Linux-based** managed desktop, not ChromeOS.

On real Chromebook hardware, the supported path is:

1. **Enable Developer Mode** on the Chromebook.
2. **Flash UEFI Full ROM firmware** with [MrChromebox Firmware Utility](https://mrchromebox.tech/) (highly recommended for Linux).
3. **Boot from USB** using a Pallet OS image built by `provision/build-chromebook-image.sh`.
4. Complete first-boot provisioning (or pass enrollment env vars).

Some Recovery Utility versions support **"Use local image"** — but only after **MrChromebox UEFI** firmware, and results vary. **Balena Etcher is strongly recommended.**

- ✅ **Balena Etcher** — flash `pallet-os-chromebook.img` (from GitHub Releases)
- ❌ **Chromebook Recovery Utility on stock firmware** — will not work (ChromeOS images only)

### Why MrChromebox?

Stock Chromebook firmware boots ChromeOS verified images only. MrChromebox replaces boot firmware with standard UEFI so Ubuntu/Pallet OS can boot from USB or internal disk — the same path used by GalliumOS, ChrUbuntu, and mainstream Linux-on-Chromebook guides.

## Supported models

Pallet OS targets **x86_64 Chromebooks** with MrChromebox UEFI firmware. ARM Chromebooks (e.g. many MediaTek models) are **not** supported in v1.

Check your device on the [MrChromebox supported devices list](https://mrchromebox.tech/supported-devices.html).

## Quick install flow

```bash
# On a build machine (Ubuntu):
cd pallet-os
sudo ./provision/build-chromebook-image.sh

# Flash USB (replace sdX):
sudo dd if=build/pallet-os-chromebook.img of=/dev/sdX bs=4M status=progress && sync

# On Chromebook: boot USB, first boot runs provisioner.
# Or on running Ubuntu install:
curl -fsSL https://raw.githubusercontent.com/your-org/pallet-os/main/provision/install-pallet-os.sh | sudo bash -s -- \
  # with env:
  PALLET_SERVER_URL=https://api.your-domain.com \
  PALLET_ENROLLMENT_TOKEN=plt_...
```

## Hardware notes

- **Wi‑Fi / touchpad**: Ubuntu 24.04 includes most Intel Chromebook drivers. Some models need `linux-firmware` updates or model-specific quirks.
- **Android (Waydroid)**: Requires `binder_linux` and `ashmem` kernel modules — provisioner loads these when available.
- **Battery / ACPI**: Exposed via standard Linux power_supply; shell reads `/sys/class/power_supply`.

## Internal disk install

After booting the USB installer successfully, use Ubuntu's installer or copy the rootfs to internal eMMC/SSD with `dd` or `rsync` + GRUB — same as any UEFI Linux install.
