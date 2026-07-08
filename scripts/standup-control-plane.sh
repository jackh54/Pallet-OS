#!/usr/bin/env bash
# Pallet OS — one-command control plane bootstrap (local dev or Docker)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Pallet OS control plane setup"

if command -v docker >/dev/null 2>&1 && [[ "${PALLET_USE_DOCKER:-1}" == "1" ]]; then
  echo "Starting Docker Compose stack (API + local dashboard proxy)..."
  cd "$ROOT"
  docker compose up -d --build
  echo ""
  echo "Control plane ready:"
  echo "  API:       http://localhost:8787"
  echo "  Dashboard: http://localhost:3000"
  echo "  Admin:     admin / pallet-dev-secret (change in production)"
  exit 0
fi

echo "Installing server dependencies..."
cd "$ROOT/server"
npm install
npm run db:migrate

if [[ ! -f .dev.vars ]]; then
  cat > .dev.vars <<'EOF'
ADMIN_PASSWORD=pallet-dev-secret
JWT_SECRET=dev-jwt-secret-change-me-in-production
EOF
  echo "Created server/.dev.vars"
fi

echo "Starting Cloudflare Worker locally on :8787"
echo "Run dashboard separately: cd dashboard && npm install && npm run dev"
npm run dev
