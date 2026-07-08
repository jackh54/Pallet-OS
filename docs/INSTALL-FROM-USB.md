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

## Quick checklist

- [ ] Ubuntu installed to **internal disk** (not Try Ubuntu)
- [ ] Vars passed **on sudo line** or in `/etc/pallet/enroll.env`
- [ ] New enroll token from dashboard
- [ ] Reboot after provision
