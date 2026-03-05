#!/usr/bin/env bash
set -euo pipefail

REMOTE_NAME=""
BRANCH_NAME=""
FORCE_SYNC=0
QUIET=0
HOOK_MODE=0

usage() {
  cat <<'EOF'
Usage: sync-windows-backup.sh [options]

Pushes windows-app subtree to a dedicated backup remote.

Options:
  --remote <name>    Override backup remote name.
  --branch <name>    Override backup branch name.
  --force            Force sync even when latest commit did not touch windows-app.
  --quiet            Reduce output.
  --hook             Internal mode for post-commit hook.
  -h, --help         Show help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote)
      REMOTE_NAME="${2:-}"
      shift 2
      ;;
    --branch)
      BRANCH_NAME="${2:-}"
      shift 2
      ;;
    --force)
      FORCE_SYNC=1
      shift
      ;;
    --quiet)
      QUIET=1
      shift
      ;;
    --hook)
      HOOK_MODE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

ENABLED="$(git config --bool --get windows.backup.enabled || echo "false")"
if [[ "$ENABLED" != "true" ]]; then
  if [[ $QUIET -eq 0 && $HOOK_MODE -eq 0 ]]; then
    echo "windows backup sync is disabled (windows.backup.enabled=false)."
  fi
  exit 0
fi

REMOTE_NAME="${REMOTE_NAME:-$(git config --get windows.backup.remote || echo "windows-private")}"
BRANCH_NAME="${BRANCH_NAME:-$(git config --get windows.backup.branch || echo "main")}"

if ! git remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
  echo "Backup remote '$REMOTE_NAME' is not configured." >&2
  exit 1
fi

if [[ $FORCE_SYNC -eq 0 ]]; then
  if git rev-parse --verify HEAD^ >/dev/null 2>&1; then
    if ! git diff-tree --no-commit-id --name-only -r HEAD | grep -Eq '^windows-app/'; then
      [[ $QUIET -eq 0 ]] && echo "No windows-app changes in latest commit. Skipping backup sync."
      exit 0
    fi
  fi
fi

[[ $QUIET -eq 0 ]] && echo "Syncing windows-app subtree to $REMOTE_NAME/$BRANCH_NAME ..."
git subtree push --prefix windows-app "$REMOTE_NAME" "$BRANCH_NAME"
[[ $QUIET -eq 0 ]] && echo "windows-app backup sync complete."
