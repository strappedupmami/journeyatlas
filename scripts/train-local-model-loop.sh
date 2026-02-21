#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

INTERVAL_SECONDS="${INTERVAL_SECONDS:-900}"
RUN_FOREVER="${RUN_FOREVER:-0}"
DATASET="${DATASET:-atlas-concierge/kb/training/local_reasoner_training.jsonl}"
MAX_VOCAB="${MAX_VOCAB:-1000}"
PRUNE_TARGET_VOCAB="${PRUNE_TARGET_VOCAB:-800}"
MIN_TOKEN_FREQ="${MIN_TOKEN_FREQ:-1}"
MIN_HOLDOUT_ACCURACY="${MIN_HOLDOUT_ACCURACY:-0.55}"
RUN_TAG="${RUN_TAG:-}"
ALLOW_BELOW_THRESHOLD="${ALLOW_BELOW_THRESHOLD:-0}"

run_once() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] training Swift local travel-design model..."
  train_args=(
    --dataset "$DATASET"
    --max-vocab "$MAX_VOCAB"
    --prune-target-vocab "$PRUNE_TARGET_VOCAB"
    --min-token-freq "$MIN_TOKEN_FREQ"
    --min-holdout-accuracy "$MIN_HOLDOUT_ACCURACY"
  )
  if [[ -n "$RUN_TAG" ]]; then
    train_args+=(--run-tag "$RUN_TAG")
  fi
  if [[ "$ALLOW_BELOW_THRESHOLD" == "1" ]]; then
    train_args+=(--allow-below-threshold)
  fi
  python3 ./scripts/train_swift_travel_design_model.py "${train_args[@]}"
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Swift travel-design model training complete"
}

run_once

if [[ "$RUN_FOREVER" == "1" ]]; then
  while true; do
    sleep "$INTERVAL_SECONDS"
    run_once || echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] training failed; retrying after interval"
  done
fi
