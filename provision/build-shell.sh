#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${PALLET_VERSION:-1.0.0}"
cd "$REPO_ROOT/shell/frontend"
npm install
npm run build
mkdir -p "$REPO_ROOT/shell/cmd/pallet-shell/dist"
cp -r dist/* "$REPO_ROOT/shell/cmd/pallet-shell/dist/"
cd "$REPO_ROOT/shell/cmd/pallet-shell"
go build -ldflags "-X main.shellVersion=${VERSION} -X main.agentVersionLabel=${VERSION}" -o "$REPO_ROOT/dist/pallet-shell" .
