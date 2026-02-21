#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW_DIR="$ROOT_DIR/.github/workflows"
EXIT_CODE=0

if [[ ! -d "$WORKFLOW_DIR" ]]; then
  echo "No workflow directory found; skipping trust-boundary checks."
  exit 0
fi

while IFS= read -r -d '' workflow; do
  if grep -qE '^[[:space:]]*pull_request_target:' "$workflow"; then
    echo "ERROR: pull_request_target is disallowed in $workflow"
    EXIT_CODE=1
  fi

  if grep -qE '^[[:space:]]*secrets:[[:space:]]*inherit[[:space:]]*$' "$workflow"; then
    echo "ERROR: secrets: inherit is disallowed in $workflow"
    EXIT_CODE=1
  fi

  if grep -qE '^[[:space:]]*permissions:[[:space:]]*write-all[[:space:]]*$' "$workflow"; then
    echo "ERROR: permissions: write-all is disallowed in $workflow"
    EXIT_CODE=1
  fi

  if ! grep -qE '^[[:space:]]*permissions:' "$workflow"; then
    echo "ERROR: workflow missing explicit permissions block: $workflow"
    EXIT_CODE=1
  fi
done < <(find "$WORKFLOW_DIR" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0)

exit "$EXIT_CODE"

