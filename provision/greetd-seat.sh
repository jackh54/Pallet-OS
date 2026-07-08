#!/usr/bin/env bash
# Ensure greetd + seatd can hand GPU access to the pallet session user.
set -euo pipefail

PALLET_USER="${PALLET_USER:-pallet}"

echo "==> Seat / DRM access for greetd sessions"

DEBIAN_FRONTEND=noninteractive apt-get install -y greetd seatd polkitd 2>/dev/null || \
  apt-get install -y greetd seatd policykit-1 2>/dev/null || true

systemctl enable --now seatd 2>/dev/null || true

# Ubuntu seatd socket is often root:video; some distros use a 'seat' group.
if ! getent group seat >/dev/null; then
  groupadd -r seat 2>/dev/null || groupadd seat 2>/dev/null || true
fi

for grp in seat video render input audio; do
  if getent group "$grp" >/dev/null; then
    usermod -aG "$grp" "$PALLET_USER" 2>/dev/null || true
  fi
done

if [[ ! -f /etc/pam.d/greetd ]]; then
  install -m 0644 /dev/stdin /etc/pam.d/greetd <<'EOF'
@include common-auth
@include common-account
@include common-session
session optional pam_systemd.so
EOF
fi

echo "    pallet groups: $(id -Gn "$PALLET_USER" 2>/dev/null || echo unknown)"
echo "    seatd socket: $(ls -l /run/seatd.sock 2>/dev/null || echo missing)"
echo "    DRM device: $(ls -l /dev/dri/card0 2>/dev/null || echo missing)"
