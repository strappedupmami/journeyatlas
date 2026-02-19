#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW_DIR="$ROOT_DIR/.github/workflows"

if [[ ! -d "$WORKFLOW_DIR" ]]; then
  echo "No workflow directory found; skipping pinning check."
  exit 0
fi

EXIT_CODE=0
while IFS= read -r use_ref; do
  action_ref="${use_ref#uses:}"
  action_ref="$(echo "$action_ref" | xargs)"

  [[ -z "$action_ref" ]] && continue
  [[ "$action_ref" == ./* ]] && continue
  [[ "$action_ref" == docker://* ]] && continue

  if [[ ! "$action_ref" =~ @[0-9a-f]{40}$ ]]; then
    echo "ERROR: Workflow action must be SHA pinned: $action_ref"
    EXIT_CODE=1
  fi
done < <(grep -RhoE 'uses:[[:space:]]*[^[:space:]]+' "$WORKFLOW_DIR")

exit "$EXIT_CODE"
