#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVENT_NAME="${GITHUB_EVENT_NAME:-}"
ACTOR="${GITHUB_ACTOR:-}"
BASE_REF="${GITHUB_BASE_REF:-}"

# Only enforce on dependency-bot pull requests.
if [[ "$EVENT_NAME" != "pull_request" ]]; then
  exit 0
fi

if [[ "$ACTOR" != "dependabot[bot]" && "$ACTOR" != "renovate[bot]" ]]; then
  exit 0
fi

if [[ -z "$BASE_REF" ]]; then
  echo "ERROR: GITHUB_BASE_REF is required for dependency PR scope verification."
  exit 1
fi

cd "$ROOT_DIR"

git fetch --no-tags --prune --depth=1 origin "$BASE_REF" >/dev/null 2>&1 || true

changed_files="$(git diff --name-only "origin/$BASE_REF...HEAD" || true)"

if [[ -z "$changed_files" ]]; then
  echo "No changed files detected for dependency-bot PR."
  exit 0
fi

exit_code=0
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  if [[ "$file" =~ ^package\.json$ ]] \
    || [[ "$file" =~ ^package-lock\.json$ ]] \
    || [[ "$file" =~ ^atlas-concierge/Cargo\.lock$ ]] \
    || [[ "$file" =~ ^atlas-concierge/Cargo\.toml$ ]] \
    || [[ "$file" =~ ^atlas-concierge/crates/.+/Cargo\.toml$ ]] \
    || [[ "$file" =~ ^\.github/dependabot\.yml$ ]]; then
    continue
  fi

  echo "ERROR: dependency-bot PR modified out-of-scope file: $file"
  exit_code=1
done <<< "$changed_files"

exit "$exit_code"

