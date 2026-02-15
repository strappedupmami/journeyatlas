#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/homepage"

PORT="${PORT:-5500}"
printf "Serving homepage on http://localhost:%s\n" "$PORT"
python3 -m http.server "$PORT"
