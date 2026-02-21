#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

INTERVAL_SECONDS="${INTERVAL_SECONDS:-900}"
RUN_FOREVER="${RUN_FOREVER:-0}"

run_once() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] training local model..."
  (cd atlas-concierge && cargo run -q -p atlas-cli -- model train-local-reasoner)
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] training complete"
}

run_once

if [[ "$RUN_FOREVER" == "1" ]]; then
  while true; do
    sleep "$INTERVAL_SECONDS"
    run_once || echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] training failed; retrying after interval"
  done
fi
