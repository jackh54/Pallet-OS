#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${PALLET_VERSION:-1.0.0}"
cd "$REPO_ROOT/agent"
mkdir -p "$REPO_ROOT/dist"
go build -ldflags "-X main.agentVersion=${VERSION}" -o "$REPO_ROOT/dist/pallet-agent" .
