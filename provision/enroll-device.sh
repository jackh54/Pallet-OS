#!/usr/bin/env bash
# One-command enroll on an already-provisioned device
set -euo pipefail
SERVER_URL="${1:-${PALLET_SERVER_URL:-}}"
ENROLL_TOKEN="${2:-${PALLET_ENROLLMENT_TOKEN:-}}"

if [[ -f /etc/pallet/enroll.env ]]; then
  # shellcheck disable=SC1091
  source /etc/pallet/enroll.env
  SERVER_URL="${SERVER_URL:-${PALLET_SERVER_URL:-}}"
  ENROLL_TOKEN="${ENROLL_TOKEN:-${PALLET_ENROLLMENT_TOKEN:-}}"
fi

if [[ -z "$SERVER_URL" || -z "$ENROLL_TOKEN" ]]; then
  echo "Usage:"
  echo "  sudo PALLET_SERVER_URL=https://api.example.com PALLET_ENROLLMENT_TOKEN=plt_... $0"
  echo "  sudo $0 https://api.example.com plt_..."
  exit 1
fi

if [[ ! -f /etc/pallet/agent.json ]]; then
  mkdir -p /etc/pallet
  cat > /etc/pallet/agent.json <<EOF
{
  "server_url": "$SERVER_URL",
  "device_id": "",
  "device_token": "",
  "device_key": ""
}
EOF
  chmod 600 /etc/pallet/agent.json
fi

pallet-agent -server "$SERVER_URL" -enroll "$ENROLL_TOKEN" -config /etc/pallet/agent.json
systemctl enable --now pallet-agent
