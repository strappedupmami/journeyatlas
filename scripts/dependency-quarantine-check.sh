#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_PATH=""
SUSPICIOUS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --report)
      REPORT_PATH="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$REPORT_PATH" ]]; then
  REPORT_PATH="$ROOT_DIR/artifacts/dependency-quarantine-report.md"
fi

mkdir -p "$(dirname "$REPORT_PATH")"
cd "$ROOT_DIR"

EVENT_NAME="${GITHUB_EVENT_NAME:-local}"
ACTOR="${GITHUB_ACTOR:-local}"
BASE_REF="${GITHUB_BASE_REF:-}"

resolve_range() {
  if [[ "$EVENT_NAME" == "pull_request" && -n "$BASE_REF" ]]; then
    git fetch --no-tags --prune --depth=1 origin "$BASE_REF" >/dev/null 2>&1 || true
    echo "origin/$BASE_REF...HEAD"
    return
  fi

  if git rev-parse --verify HEAD^ >/dev/null 2>&1; then
    echo "HEAD^...HEAD"
    return
  fi

  local empty_tree
  empty_tree="$(git hash-object -t tree /dev/null)"
  echo "${empty_tree}...HEAD"
}

DIFF_RANGE="$(resolve_range)"
CHANGED_FILES="$(git diff --name-only "$DIFF_RANGE" || true)"

declare -a triggers=()

record_trigger() {
  local trigger="$1"
  for existing in "${triggers[@]:-}"; do
    if [[ "$existing" == "$trigger" ]]; then
      return
    fi
  done
  triggers+=("$trigger")
  SUSPICIOUS=true
}

is_bot_pr=false
if [[ "$EVENT_NAME" == "pull_request" && ( "$ACTOR" == "dependabot[bot]" || "$ACTOR" == "renovate[bot]" ) ]]; then
  is_bot_pr=true
fi

if [[ "$is_bot_pr" == true ]]; then
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
    record_trigger "Dependency bot changed out-of-scope file: $file"
  done <<< "$CHANGED_FILES"

  if echo "$CHANGED_FILES" | grep -Eq '^(\.github/workflows/|scripts/)'; then
    record_trigger "Dependency bot changed workflow/script path."
  fi
fi

while IFS= read -r file; do
  [[ -z "$file" ]] && continue

  if [[ "$file" == "package.json" ]]; then
    FILE_DIFF="$(git diff --unified=0 "$DIFF_RANGE" -- "$file" || true)"
    if echo "$FILE_DIFF" | grep -Eq '^\+.*"(preinstall|install|postinstall|prepare|prepack|postpack)"[[:space:]]*:'; then
      record_trigger "Added npm lifecycle script hook in package.json."
    fi
    if echo "$FILE_DIFF" | grep -Eq '^\+.*":[[:space:]]*"(git\+https?://|git\+ssh://|https?://|github:|file:|link:)'; then
      record_trigger "Added non-registry npm dependency source (git/url/file/link)."
    fi
  fi

  if [[ "$file" =~ ^atlas-concierge(/crates/.+)?/Cargo\.toml$ ]]; then
    FILE_DIFF="$(git diff --unified=0 "$DIFF_RANGE" -- "$file" || true)"
    if echo "$FILE_DIFF" | grep -Eq '^\+.*\b(git|path)[[:space:]]*='; then
      record_trigger "Added Cargo git/path dependency in $file."
    fi
  fi
done <<< "$CHANGED_FILES"

LOCKFILE_CHURN=0
while IFS=$'\t' read -r added deleted file; do
  [[ -z "${file:-}" ]] && continue
  if [[ "$file" == "package-lock.json" || "$file" == "atlas-concierge/Cargo.lock" ]]; then
    if [[ "$added" == "-" || "$deleted" == "-" ]]; then
      LOCKFILE_CHURN=999999
    else
      LOCKFILE_CHURN=$((LOCKFILE_CHURN + added + deleted))
    fi
  fi
done < <(git diff --numstat "$DIFF_RANGE" || true)

if (( LOCKFILE_CHURN > 12000 )); then
  record_trigger "Lockfile churn is unusually high ($LOCKFILE_CHURN lines changed)."
fi

{
  echo "# Dependency Quarantine Report"
  echo
  echo "- Event: \`$EVENT_NAME\`"
  echo "- Actor: \`$ACTOR\`"
  echo "- Diff range: \`$DIFF_RANGE\`"
  echo "- Lockfile churn: \`$LOCKFILE_CHURN\` lines"
  echo
  echo "## Changed files"
  if [[ -z "$CHANGED_FILES" ]]; then
    echo "_No changed files detected._"
  else
    while IFS= read -r file; do
      [[ -z "$file" ]] && continue
      echo "- \`$file\`"
    done <<< "$CHANGED_FILES"
  fi
  echo
  echo "## Quarantine triggers"
  if [[ ${#triggers[@]} -eq 0 ]]; then
    echo "- None"
  else
    for t in "${triggers[@]}"; do
      echo "- $t"
    done
  fi
} > "$REPORT_PATH"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "suspicious=$SUSPICIOUS"
    echo "report_path=$REPORT_PATH"
    echo "lockfile_churn=$LOCKFILE_CHURN"
  } >> "$GITHUB_OUTPUT"
fi

if [[ "$SUSPICIOUS" == true ]]; then
  echo "suspicious=true"
  echo "Dependency quarantine triggered. See: $REPORT_PATH"
  exit 1
fi

echo "suspicious=false"
echo "Dependency update passed quarantine checks. Report: $REPORT_PATH"
exit 0
