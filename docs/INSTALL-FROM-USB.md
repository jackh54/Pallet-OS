# Install Pallet OS from Ubuntu Desktop USB

## Do NOT use "Try Ubuntu" for the final install

**Try Ubuntu** runs in RAM. Anything you install is **gone after reboot**.

You must **install Ubuntu to the internal disk first**, then provision Pallet OS.

---

## Correct steps

### 1. Boot Ubuntu USB on Chromebook
Esc → pick USB → **Install Ubuntu** (not Try Ubuntu)

### 2. Install Ubuntu to internal drive
- Erase disk and install Ubuntu (or manual partition — use whole disk)
- Create user, finish install, **reboot**
- **Remove USB** when prompted

### 3. Boot into installed Ubuntu
Log in to the desktop on internal drive.

### 4. Install Pallet OS

Open Terminal:

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/jackh54/Pallet-OS.git
cd Pallet-OS
```

**Important:** pass vars on the `sudo` line (export alone is stripped by sudo):

```bash
sudo PALLET_SERVER_URL="https://YOUR-WORKER.workers.dev" \
     PALLET_ENROLLMENT_TOKEN="plt_YOUR_TOKEN" \
     ./provision/install-pallet-os.sh
```

Or use flags:

```bash
sudo ./provision/install-pallet-os.sh \
  --server "https://YOUR-WORKER.workers.dev" \
  --token "plt_YOUR_TOKEN"
```

Or save vars to a file first:

```bash
sudo mkdir -p /etc/pallet
sudo tee /etc/pallet/enroll.env <<EOF
PALLET_SERVER_URL=https://YOUR-WORKER.workers.dev
PALLET_ENROLLMENT_TOKEN=plt_YOUR_TOKEN
EOF
sudo chmod 600 /etc/pallet/enroll.env
sudo ./provision/install-pallet-os.sh
```

### 5. Reboot

```bash
sudo reboot
```

You should autologin to the Pallet OS shelf desktop.

---

## If enrollment was skipped

```bash
cd Pallet-OS
sudo PALLET_SERVER_URL="https://YOUR-WORKER.workers.dev" \
     PALLET_ENROLLMENT_TOKEN="plt_NEW_TOKEN" \
     ./provision/enroll-device.sh
```

Create a **new** enroll token in the dashboard (old one may be used).

---

## Waydroid warning

`group 'waydroid' does not exist` is normal **before** Waydroid installs. The script now handles this. Waydroid may still fail on live USB — that's OK; install it after reboot on the real system.

---

## WiFi not connecting on boot / heartbeat "server misbehaving"

That error means **no internet** (usually WiFi didn't auto-connect).

**Connect and save WiFi once:**

```bash
sudo pallet-connect-wifi "YourNetworkName" "YourPassword"
```

Or without the helper:

```bash
nmcli device wifi connect "YourNetworkName" password "YourPassword"
```

Then reboot — it should reconnect automatically.

**Check WiFi status:**

```bash
nmcli device status
nmcli connection show --active
sudo tail -20 /var/log/pallet/wifi.log
```

**Re-apply WiFi auto-connect fix:**

```bash
cd ~/Pallet-OS && git pull
sudo ./provision/install-pallet-os.sh
sudo reboot
```

---

## Black screen: Permission denied on /dev/dri/card0 (AMD)

If `session.log` shows:

```
Failed to open DRM node '/dev/dri/card0': Permission denied
Failed to initialize EGL context
graphics mode: hardware
```

The GPU driver loaded (`amdgpu` in dmesg is fine) but **greetd did not hand GPU access to labwc**.

**Immediate fix** (skip `seat` if that group doesn't exist on Ubuntu):

```bash
sudo groupadd seat 2>/dev/null || true
sudo usermod -aG render,video,input pallet
getent group seat >/dev/null && sudo usermod -aG seat pallet
sudo mkdir -p /etc/pallet
sudo touch /etc/pallet/force-software-rendering
sudo reboot
```

**Full fix:**

```bash
cd ~/Pallet-OS && git pull
sudo ./provision/install-pallet-os.sh
sudo reboot
```

---

## Black screen + brief driver error (i915 / drm / firmware)

If you see a flash of text mentioning **i915**, **drm**, **firmware**, or **gpu** then a black screen, the Intel GPU driver failed. Force CPU rendering:

```bash
sudo mkdir -p /etc/pallet
sudo touch /etc/pallet/force-software-rendering
sudo reboot
```

**Check what failed:**

```bash
dmesg | grep -iE 'i915|drm|gpu|firmware|failed'
lspci -k | grep -A3 -i vga
sudo tail -30 /var/log/pallet/session.log
```

**Full fix from repo:**

```bash
cd ~/Pallet-OS && git pull
sudo ./provision/install-pallet-os.sh
sudo reboot
```

---

## Black screen after reboot (mouse cursor, no desktop)

The shelf is a web UI — a browser must open it. If you only see a mouse cursor:

**Fastest fix (keeps enrollment):**

```bash
cd ~/Pallet-OS && git pull
sudo ./provision/install-pallet-os.sh
sudo reboot
```

**Check logs from TTY (`Ctrl+Alt+F3`):**

```bash
sudo tail -50 /var/log/pallet/desktop.log
sudo tail -20 /var/log/pallet/session.log
```

**Manual test as pallet user:**

```bash
sudo -u pallet /usr/local/bin/pallet-shell-launch
```

**Confirm greetd + seatd:**

```bash
grep -E '^(command|user|vt)' /etc/greetd/config.toml
# command should be /usr/local/bin/pallet-session
sudo systemctl enable --now seatd greetd
```

**Emergency fallback to Ubuntu desktop:**

```bash
sudo systemctl disable greetd
sudo systemctl enable gdm3
sudo reboot
```

## Quick checklist

- [ ] Ubuntu installed to **internal disk** (not Try Ubuntu)
- [ ] Vars passed **on sudo line** or in `/etc/pallet/enroll.env`
- [ ] New enroll token from dashboard
- [ ] Reboot after provision
