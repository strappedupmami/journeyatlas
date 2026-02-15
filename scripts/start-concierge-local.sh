#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/atlas-concierge"

export ATLAS_API_KEY="${ATLAS_API_KEY:-dev-atlas-key}"
export ATLAS_BIND="${ATLAS_BIND:-0.0.0.0:8080}"
export ATLAS_KB_ROOT="${ATLAS_KB_ROOT:-kb}"

printf "\n[Atlas Concierge] Starting API on %s with kb=%s\n" "$ATLAS_BIND" "$ATLAS_KB_ROOT"
printf "API Key: %s\n" "$ATLAS_API_KEY"
printf "Open UI: %s\n\n" "$ROOT_DIR/homepage/concierge-local.html"

cargo run -p atlas-api
