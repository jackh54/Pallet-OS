# Architecture

```
┌──────────────────── Vercel ────────────────────┐
│  Admin Dashboard (Next.js)                     │
│  - Device list, policy editor, commands        │
└────────────────────┬───────────────────────────┘
                     │ HTTPS + Bearer JWT
┌────────────────────▼───────────────────────────┐
│  Cloudflare Worker API (or Docker local API)   │
│  - Enrollment, policy store, command queue     │
│  - D1 SQLite (prod) / better-sqlite3 (local)   │
└───────────────┬────────────────────────────────┘
                │ HTTPS heartbeats + commands
┌───────────────▼────────────────────────────────┐
│  Chromebook running Pallet OS                    │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────┐ │
│  │ pallet-agent│  │ pallet-shell │  │ Waydroid│ │
│  │ (Go)        │  │ (Go+React)   │  │ Android │ │
│  └──────┬──────┘  └──────┬───────┘  └────┬────┘ │
│         │ applies policy  │ shelf/UI      │ apps │
│         ▼                 ▼               ▼      │
│  Chromium policies   labwc compositor   Play/APK │
└──────────────────────────────────────────────────┘
```

## Policy flow

1. Admin updates global policy in dashboard → `PUT /api/v1/admin/policy`
2. Server stores JSON in D1, queues `apply_policy` command
3. Agent heartbeat receives merged policy + pending commands
4. Agent writes `/etc/chromium/policies/managed/pallet_policy.json`
5. Agent reconciles Android apps via Waydroid
6. Shell reads `/var/lib/pallet/shell-policy.json` and wallpaper

## Command flow

1. Admin sends `POST /api/v1/admin/devices/:id/commands`
2. Command row inserted with `pending` status
3. Next heartbeat returns command; status → `acknowledged`
4. Agent executes (lock/reboot/wipe/…)
5. Agent `POST /api/v1/device/commands/:id/complete`

## Base OS decision

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| Ubuntu 24.04 LTS | Waydroid support, Chromebook community, unattended-upgrades | Not immutable | **Selected** |
| Debian | Stable, minimal | Older packages for Wayland/Waydroid | Fallback |
| Fedora Silverblue | Immutable | Waydroid friction, Chromebook support | No |
| Yocto/Buildroot | Tiny image | Huge build cost, slow iteration | No |

## Shell decision

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| Custom wlroots shell | Pixel-perfect ChromeOS | Months of compositor work | Future |
| labwc + custom React shell | Fast, maintainable, real windows | Not 100% pixel match | **Selected** |
