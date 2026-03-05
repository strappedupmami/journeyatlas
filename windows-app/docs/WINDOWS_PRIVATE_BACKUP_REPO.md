# Windows App Private Backup Repo

This sets up a dedicated private Git repo for `windows-app` and syncs to it automatically.

## What it does
- Adds a dedicated remote (default: `windows-private`)
- Installs a `post-commit` hook in this repo
- On each commit that touches `windows-app`, pushes `windows-app` subtree to the private repo branch
- If an existing `post-commit` hook exists, setup saves a backup at `.git/hooks/post-commit.pre-windows-backup.bak`

## One-time setup
Run from repo root:

```bash
chmod +x windows-app/scripts/setup-windows-backup-repo.sh windows-app/scripts/sync-windows-backup.sh
./windows-app/scripts/setup-windows-backup-repo.sh \
  --remote-url git@github.com:YOUR_ORG/YOUR_PRIVATE_WINDOWS_REPO.git \
  --branch main
```

## Manual sync (any time)

```bash
./windows-app/scripts/sync-windows-backup.sh --force
```

## Config values
- `windows.backup.enabled` (`true`/`false`)
- `windows.backup.remote` (default `windows-private`)
- `windows.backup.branch` (default `main`)

Disable auto-sync:

```bash
git config windows.backup.enabled false
```

Re-enable:

```bash
git config windows.backup.enabled true
```
