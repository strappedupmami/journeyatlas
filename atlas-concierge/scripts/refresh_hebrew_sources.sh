#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/docs/source-cache/hebrew"
MANIFEST="$ROOT_DIR/scripts/hebrew_sources_manifest.txt"

mkdir -p "$OUT_DIR"

while IFS= read -r url; do
  [[ -z "$url" ]] && continue
  file_name="$(echo "$url" | sed 's|https\?://||; s|[^a-zA-Z0-9._-]|_|g')"
  target="$OUT_DIR/${file_name}.html"

  echo "Fetching: $url"
  curl -L --fail --silent --show-error "$url" -o "$target"
  echo "Saved -> $target"
done < "$MANIFEST"

echo "Done. Review cached HTML files and update kb/research/*.md + *.json with validated facts."
