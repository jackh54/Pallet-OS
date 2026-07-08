#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT/agent"
mkdir -p "$REPO_ROOT/dist"
go build -o "$REPO_ROOT/dist/pallet-agent" .
