#!/usr/bin/env bash
# Integration smoke test for Pallet OS API (no hardware required)
set -euo pipefail
API="${PALLET_API_URL:-http://127.0.0.1:8787}"

echo "==> Health"
curl -fsS "$API/health" | jq .

echo "==> Admin login"
TOKEN=$(curl -fsS -X POST "$API/api/v1/admin/login" \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"pallet-dev-secret"}' | jq -r .token)
test -n "$TOKEN"

echo "==> Create enrollment token"
ENROLL=$(curl -fsS -X POST "$API/api/v1/admin/enrollment-tokens" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"label":"test"}' | jq -r .token)
test -n "$ENROLL"

echo "==> Enroll device"
DEVICE_KEY="test-device-key-$(date +%s)"
ENROLL_RESP=$(curl -fsS -X POST "$API/api/v1/device/enroll" \
  -H 'Content-Type: application/json' \
  -d "{\"enrollment_token\":\"$ENROLL\",\"hostname\":\"test-vm\",\"device_key\":\"$DEVICE_KEY\"}")
DEVICE_ID=$(echo "$ENROLL_RESP" | jq -r .device_id)
DEVICE_TOKEN=$(echo "$ENROLL_RESP" | jq -r .device_token)

echo "==> Heartbeat"
curl -fsS -X POST "$API/api/v1/device/heartbeat" \
  -H "Authorization: Bearer $DEVICE_TOKEN" \
  -H "X-Device-Key: $DEVICE_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"hostname":"test-vm","uptime_seconds":42,"ip_addresses":["127.0.0.1"],"agent_version":"1.0.0","os_version":"Pallet OS Test","installed_apps":[]}' | jq .

echo "==> List devices"
curl -fsS "$API/api/v1/admin/devices" -H "Authorization: Bearer $TOKEN" | jq '.devices | length'

echo "==> Queue reboot command"
curl -fsS -X POST "$API/api/v1/admin/devices/$DEVICE_ID/commands" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"type":"reboot"}' | jq .

echo "All API smoke tests passed."
