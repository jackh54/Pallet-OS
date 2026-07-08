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

## Black screen after reboot (mouse cursor, no desktop)

`pallet-shell` is an HTTP server — Chromium must open it as a fullscreen window.

1. Press **Ctrl+Alt+F3** to get a text console, log in, then run:

```bash
# One-line fix if you have the repo cloned:
cd ~/Pallet-OS && git pull
sudo install -m 0755 provision/pallet-shell-launch.sh /usr/local/bin/pallet-shell-launch
sudo install -m 0644 provision/labwc/rc.xml /home/pallet/.config/labwc/rc.xml
sudo chown pallet:pallet /home/pallet/.config/labwc/rc.xml
sudo reboot
```

2. Or apply manually without git:

```bash
sudo tee /usr/local/bin/pallet-shell-launch >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
PORT="${PALLET_SHELL_PORT:-7420}"
URL="http://127.0.0.1:${PORT}"
/usr/local/bin/pallet-shell &
for i in $(seq 1 50); do curl -sf "$URL/api/config" && break; sleep 0.2; done
export GDK_BACKEND=wayland
exec chromium --ozone-platform=wayland --kiosk --app="$URL" --no-first-run
EOF
sudo chmod 755 /usr/local/bin/pallet-shell-launch
sudo sed -i 's|pallet-shell|/usr/local/bin/pallet-shell-launch|' /home/pallet/.config/labwc/rc.xml
sudo reboot
```

3. Confirm greetd + seatd (from PR #10):

```bash
grep -E '^(command|user|vt)' /etc/greetd/config.toml
# vt = 1, command = labwc..., user = pallet (not nested greetd)
sudo systemctl enable --now seatd greetd
```

4. Emergency fallback to Ubuntu desktop:

```bash
sudo systemctl disable greetd
sudo systemctl enable gdm3
sudo reboot
```

Launch log: `/run/user/1000/pallet/shell-launch.log` (uid may differ).

---

## Quick checklist

- [ ] Ubuntu installed to **internal disk** (not Try Ubuntu)
- [ ] Vars passed **on sudo line** or in `/etc/pallet/enroll.env`
- [ ] New enroll token from dashboard
- [ ] Reboot after provision
