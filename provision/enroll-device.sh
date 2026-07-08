#!/usr/bin/env bash
# One-command enroll on an already-provisioned device
set -euo pipefail
SERVER_URL="${1:-${PALLET_SERVER_URL:-}}"
ENROLL_TOKEN="${2:-${PALLET_ENROLLMENT_TOKEN:-}}"
if [[ -z "$SERVER_URL" || -z "$ENROLL_TOKEN" ]]; then
  echo "Usage: PALLET_SERVER_URL=... PALLET_ENROLLMENT_TOKEN=... $0"
  exit 1
fi
sudo pallet-agent -server "$SERVER_URL" -enroll "$ENROLL_TOKEN" -config /etc/pallet/agent.json
sudo systemctl enable --now pallet-agent
