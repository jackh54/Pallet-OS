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

### Download from GitHub Releases (CI-built)

1. **Actions** → **Build Chromebook USB image** runs on tags (`v1.0.0`) or manual dispatch
2. Download from **Releases**: `pallet-os-chromebook.img.zst` + `.sha256`
3. `zstd -d pallet-os-chromebook.img.zst`
4. Flash with **Balena Etcher** → `pallet-os-chromebook.img`
5. Boot Chromebook from USB (MrChromebox UEFI required)

```bash
# Publish a release build:
git tag v1.0.0 && git push origin v1.0.0
```

### Or build locally

```bash
cd pallet-os
sudo ./provision/build-chromebook-image.sh
sudo dd if=build/pallet-os-chromebook.img of=/dev/sdX bs=4M status=progress && sync
```

### After USB boot

First boot runs the provisioner automatically. Or on an existing Ubuntu install:

```bash
export PALLET_SERVER_URL=https://api.your-domain.com
export PALLET_ENROLLMENT_TOKEN=plt_...
sudo ./provision/install-pallet-os.sh && sudo reboot
```

## Hardware notes

- **AMD Chromebooks (Picasso / Ryzen 3xxx)**: Audio codec `acp3x-alc5682-max98357`. Boot logs like `DMIC gpio failed err=-2` are **internal microphone only** — annoying but **do not cause a black screen**. Speakers are fixed via ALSA UCM profile (provisioner applies this automatically).
- **Display**: AMD models use `amdgpu` (not Intel `i915`). If the screen is black, use `sudo touch /etc/pallet/force-software-rendering && sudo reboot`.
- **Wi‑Fi / touchpad**: Ubuntu 24.04 includes most Intel/AMD Chromebook drivers. Some models need `linux-firmware` updates or model-specific quirks.
- **Android (Waydroid)**: Requires `binder_linux` and `ashmem` kernel modules — provisioner loads these when available.
- **Battery / ACPI**: Exposed via standard Linux power_supply; shell reads `/sys/class/power_supply`.

## Internal disk install

After booting the USB installer successfully, use Ubuntu's installer or copy the rootfs to internal eMMC/SSD with `dd` or `rsync` + GRUB — same as any UEFI Linux install.
