#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../server"
npm install
npm run db:migrate:remote
npm run deploy
echo "Set dashboard NEXT_PUBLIC_API_URL to your workers.dev URL"
