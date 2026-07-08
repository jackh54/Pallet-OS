# Testing Pallet OS without physical hardware

This guide validates the **control plane**, **agent logic**, and **shell UI** using VMs/containers. Full Waydroid + Chromebook firmware paths require real hardware or a VM with nested virt (optional).

## Prerequisites

- Docker & Docker Compose **or** Node 22 + Go 1.22
- `curl`, `jq`

## 1. Control plane smoke test

```bash
chmod +x scripts/*.sh provision/*.sh
./scripts/standup-control-plane.sh
# wait for healthy API

./scripts/test-api.sh
```

Expected: health OK, enroll token created, device enrolled, heartbeat returns policy, device listed.

## 2. Unit tests (server)

```bash
cd server
npm install
npm test
```

## 3. Agent build test

```bash
cd agent
go build -o ../dist/pallet-agent .
../dist/pallet-agent -h
```

Run agent against local API:

```bash
export PALLET_SERVER_URL=http://127.0.0.1:8787
# Create token via dashboard or test-api.sh
./dist/pallet-agent -server "$PALLET_SERVER_URL" -enroll "plt_..." -config /tmp/pallet-agent.json
```

On Linux with Chromium installed, verify policy file:

```bash
ls -la /etc/chromium/policies/managed/pallet_policy.json
```

## 4. Shell UI dev

```bash
cd shell/frontend
npm install
npm run dev
# Open http://localhost:7420
```

Production shell binary:

```bash
./provision/build-shell.sh
./dist/pallet-shell
# Open http://localhost:7420
```

## 5. VM as fake Chromebook

Use **Ubuntu 24.04 Server** in QEMU/VirtualBox/UTM:

1. Install Ubuntu, create user `pallet`
2. Clone repo, run `sudo PALLET_SERVER_URL=... PALLET_ENROLLMENT_TOKEN=... ./provision/install-pallet-os.sh`
3. Reboot into graphical session (VM must use EFI + display)
4. Confirm shelf at bottom, Chromium launches from launcher
5. In dashboard, device shows **online**

### QEMU example (UEFI, nested virt for Waydroid optional)

```bash
qemu-img create -f qcow2 pallet-test.qcow2 32G
# Boot Ubuntu 24.04 ISO with OVMF firmware, install, then provision
```

## 6. Docker-only device simulator

For CI without GUI:

```bash
docker run --rm -v "$PWD/dist/pallet-agent:/agent" alpine /agent -h
```

Heartbeat loop against local API (no policy side effects on Alpine):

```bash
# enroll first, then:
docker run --rm --network host -v /tmp/pallet-agent.json:/etc/pallet/agent.json \
  -v "$PWD/dist/pallet-agent:/usr/local/bin/pallet-agent" \
  ubuntu:24.04 /usr/local/bin/pallet-agent -config /etc/pallet/agent.json
```

## 7. Dashboard

```bash
cd dashboard
npm install
NEXT_PUBLIC_API_URL=http://127.0.0.1:8787 npm run dev
```

Login `admin` / `pallet-dev-secret`, verify devices and policy editor.

## 8. Cloudflare Workers staging

```bash
cd server
cp .dev.vars.example .dev.vars   # if provided
npm run dev                      # wrangler dev on :8787
```

Point dashboard `NEXT_PUBLIC_API_URL` to tunnel URL.

## 9. Chromebook hardware checklist

When you have a device:

- [ ] MrChromebox UEFI firmware flashed
- [ ] USB image boots
- [ ] Wi‑Fi works after provision
- [ ] Shelf + launcher visible after autologin
- [ ] Chromium policy applied (`chrome://policy`)
- [ ] Waydroid starts (`waydroid status`)
- [ ] Android app appears in launcher
- [ ] Remote lock/reboot from dashboard

## Troubleshooting

| Symptom | Check |
|---------|--------|
| Device offline | Agent service `journalctl -u pallet-agent`, server URL, TLS |
| Policy not applied | `/etc/chromium/policies/managed/`, restart Chromium |
| Black screen | `labwc`, `greetd`, seat permissions |
| Waydroid fails | `modprobe binder_linux`, CPU virt extensions |
