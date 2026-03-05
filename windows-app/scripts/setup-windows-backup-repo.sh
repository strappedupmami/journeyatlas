#!/usr/bin/env bash
set -euo pipefail

REMOTE_URL=""
REMOTE_NAME="windows-private"
BRANCH_NAME="main"
RUN_INITIAL_SYNC=1

usage() {
  cat <<'EOF'
Usage: setup-windows-backup-repo.sh --remote-url <git-url> [options]

Configures automatic backup sync for windows-app into a dedicated private repo.

Options:
  --remote-url <url>   Private backup repo URL (required).
  --remote-name <name> Git remote name to use (default: windows-private).
  --branch <name>      Backup branch name in private repo (default: main).
  --no-initial-sync    Install config + hook but skip initial push.
  -h, --help           Show help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote-url)
      REMOTE_URL="${2:-}"
      shift 2
      ;;
    --remote-name)
      REMOTE_NAME="${2:-}"
      shift 2
      ;;
    --branch)
      BRANCH_NAME="${2:-}"
      shift 2
      ;;
    --no-initial-sync)
      RUN_INITIAL_SYNC=0
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

if [[ -z "$REMOTE_URL" ]]; then
  echo "--remote-url is required." >&2
  usage
  exit 2
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOK_PATH="$REPO_ROOT/.git/hooks/post-commit"
HOOK_BACKUP_PATH="$REPO_ROOT/.git/hooks/post-commit.pre-windows-backup.bak"
SYNC_SCRIPT="$REPO_ROOT/windows-app/scripts/sync-windows-backup.sh"

if [[ ! -x "$SYNC_SCRIPT" ]]; then
  chmod +x "$SYNC_SCRIPT"
fi

if git remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
  git remote set-url "$REMOTE_NAME" "$REMOTE_URL"
else
  git remote add "$REMOTE_NAME" "$REMOTE_URL"
fi

git config windows.backup.enabled true
git config windows.backup.remote "$REMOTE_NAME"
git config windows.backup.branch "$BRANCH_NAME"

if [[ -f "$HOOK_PATH" ]] && ! grep -q "atlas_windows_backup_hook" "$HOOK_PATH"; then
  cp "$HOOK_PATH" "$HOOK_BACKUP_PATH"
  echo "Backed up existing post-commit hook to: $HOOK_BACKUP_PATH"
fi

cat >"$HOOK_PATH" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# atlas_windows_backup_hook
repo_root="$(git rev-parse --show-toplevel)"
"$repo_root/windows-app/scripts/sync-windows-backup.sh" --hook --quiet || true
EOF
chmod +x "$HOOK_PATH"

echo "Configured windows-app backup remote: $REMOTE_NAME -> $REMOTE_URL"
echo "Configured backup branch: $BRANCH_NAME"
echo "Installed post-commit hook: $HOOK_PATH"

if [[ $RUN_INITIAL_SYNC -eq 1 ]]; then
  echo "Running initial windows-app backup sync..."
  "$SYNC_SCRIPT" --remote "$REMOTE_NAME" --branch "$BRANCH_NAME" --force
fi

echo "Done. Future commits that touch windows-app will auto-sync to the private repo."
