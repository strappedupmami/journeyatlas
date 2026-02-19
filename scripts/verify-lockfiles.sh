#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-presence}"
EXIT_CODE=0

ensure_file() {
  local target="$1"
  local message="$2"
  if [[ ! -f "$target" ]]; then
    echo "ERROR: $message"
    EXIT_CODE=1
  fi
}

ensure_file "$ROOT_DIR/package-lock.json" "Missing /package-lock.json. Run: npm install --package-lock-only"
ensure_file "$ROOT_DIR/atlas-concierge/Cargo.lock" "Missing /atlas-concierge/Cargo.lock. Run: (cd atlas-concierge && cargo generate-lockfile)"

if [[ "$MODE" == "sync-check" ]]; then
  if command -v npm >/dev/null 2>&1 && [[ -f "$ROOT_DIR/package-lock.json" ]]; then
    (
      cd "$ROOT_DIR"
      npm install --package-lock-only --ignore-scripts --no-audit --fund=false >/dev/null
    )
    if ! git -C "$ROOT_DIR" diff --exit-code -- package-lock.json >/dev/null; then
      echo "ERROR: package-lock.json is out of sync with package.json."
      EXIT_CODE=1
    fi
  fi

  if command -v cargo >/dev/null 2>&1 && [[ -f "$ROOT_DIR/atlas-concierge/Cargo.lock" ]]; then
    (
      cd "$ROOT_DIR/atlas-concierge"
      cargo generate-lockfile >/dev/null
    )
    if ! git -C "$ROOT_DIR" diff --exit-code -- atlas-concierge/Cargo.lock >/dev/null; then
      echo "ERROR: atlas-concierge/Cargo.lock is out of sync with Cargo manifests."
      EXIT_CODE=1
    fi
  fi
fi

exit "$EXIT_CODE"
