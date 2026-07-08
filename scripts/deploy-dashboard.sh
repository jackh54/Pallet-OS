#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../dashboard"
npm install
vercel deploy --prod
