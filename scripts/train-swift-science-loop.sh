#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

INTERVAL_SECONDS="${INTERVAL_SECONDS:-1800}"
RUN_FOREVER="${RUN_FOREVER:-0}"
MAX_PAPERS="${MAX_PAPERS:-5000}"
INPUT_CORPUS="${INPUT_CORPUS:-atlas-concierge/kb/training/scientific_papers_seed.jsonl}"
EXTRA_INPUT_CORPUS="${EXTRA_INPUT_CORPUS:-atlas-concierge/kb/training/scientific_papers_openalex.jsonl}"
FETCH_OPENALEX="${FETCH_OPENALEX:-0}"
OPENALEX_QUERY_FILE="${OPENALEX_QUERY_FILE:-atlas-concierge/kb/training/openalex_atlas_queries.txt}"
OPENALEX_PAGES="${OPENALEX_PAGES:-20}"
OPENALEX_PER_PAGE="${OPENALEX_PER_PAGE:-100}"
OPENALEX_MAX_PAPERS="${OPENALEX_MAX_PAPERS:-25000}"
OPENALEX_FROM_YEAR="${OPENALEX_FROM_YEAR:-1990}"
OPENALEX_MAILTO="${OPENALEX_MAILTO:-}"
OPENALEX_SLEEP_MS="${OPENALEX_SLEEP_MS:-180}"
MAX_VOCAB="${MAX_VOCAB:-1400}"
PRUNE_TARGET_VOCAB="${PRUNE_TARGET_VOCAB:-512}"
MIN_TOKEN_FREQ="${MIN_TOKEN_FREQ:-1}"
MIN_HOLDOUT_ACCURACY="${MIN_HOLDOUT_ACCURACY:-0.55}"
RUN_TAG="${RUN_TAG:-swift-science}"
ALLOW_BELOW_THRESHOLD="${ALLOW_BELOW_THRESHOLD:-0}"

run_once() {
  if [[ "$FETCH_OPENALEX" == "1" ]]; then
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] fetching OpenAlex corpus"
    fetch_args=(
      --query-file "$OPENALEX_QUERY_FILE"
      --pages "$OPENALEX_PAGES"
      --per-page "$OPENALEX_PER_PAGE"
      --from-year "$OPENALEX_FROM_YEAR"
      --max-papers "$OPENALEX_MAX_PAPERS"
      --sleep-ms "$OPENALEX_SLEEP_MS"
      --output "$EXTRA_INPUT_CORPUS"
    )
    if [[ -n "$OPENALEX_MAILTO" ]]; then
      fetch_args+=(--mailto "$OPENALEX_MAILTO")
    fi
    ./scripts/fetch_openalex_atlas_papers.py "${fetch_args[@]}"
  fi

  build_inputs=("$INPUT_CORPUS")
  if [[ -f "$EXTRA_INPUT_CORPUS" ]]; then
    build_inputs+=("$EXTRA_INPUT_CORPUS")
  fi

  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] building Swift research corpus from: ${build_inputs[*]}"
  ./scripts/build_swift_research_corpus.py --input "${build_inputs[@]}" --max-papers "$MAX_PAPERS" --merge-into-base

  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] retraining Swift travel-design model"
  train_args=(
    --dataset atlas-concierge/kb/training/local_reasoner_training.jsonl
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

  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Swift travel-design model + research corpus refresh complete"
}

run_once

if [[ "$RUN_FOREVER" == "1" ]]; then
  while true; do
    sleep "$INTERVAL_SECONDS"
    run_once || echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] cycle failed; retrying after interval"
  done
fi
