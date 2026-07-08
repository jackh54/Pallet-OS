#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT/shell/frontend"
npm install
npm run build
mkdir -p "$REPO_ROOT/shell/cmd/pallet-shell/dist"
cp -r dist/* "$REPO_ROOT/shell/cmd/pallet-shell/dist/"
cd "$REPO_ROOT/shell/cmd/pallet-shell"
go build -o "$REPO_ROOT/dist/pallet-shell" .
