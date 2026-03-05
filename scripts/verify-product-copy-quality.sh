#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TARGETS=(
  "ios-app/AtlasMasaIOS/Sources"
  "macos-app/AtlasMasaMacOS/Sources"
  "android-app/app/src"
  "windows-app/AtlasMasaWindows"
  "website"
  "app"
  "components"
)

GLOBS=(
  "*.swift"
  "*.kt"
  "*.kts"
  "*.cs"
  "*.ts"
  "*.tsx"
  "*.js"
  "*.jsx"
  "*.html"
  "*.css"
)

EXCLUDES=(
  "!**/LocalReasoningEngine.swift"
  "!**/generated/**"
)

PATTERNS=(
  "nothing to see here - yet\\."
  "\\bhey gang\\b"
  "\\byo wassup\\b"
  "\\bwassup\\b"
  "\\bbootycheeks\\b"
  "\\bmami\\b"
)

PATTERN_LABELS=(
  "placeholder_empty_state"
  "casual_phrase_hey_gang"
  "casual_phrase_yo_wassup"
  "casual_phrase_wassup"
  "non_productive_phrase_bootycheeks"
  "non_productive_phrase_mami"
)

RG_ARGS=()
for glob in "${GLOBS[@]}"; do
  RG_ARGS+=("--glob" "$glob")
done
for exclude in "${EXCLUDES[@]}"; do
  RG_ARGS+=("--glob" "$exclude")
done

failures=0
for i in "${!PATTERNS[@]}"; do
  pattern="${PATTERNS[$i]}"
  label="${PATTERN_LABELS[$i]}"

  matches="$(rg -n --pcre2 "${RG_ARGS[@]}" "$pattern" "${TARGETS[@]}" || true)"
  if [[ -n "$matches" ]]; then
    echo "[copy-quality] Disallowed product copy detected: $label"
    echo "$matches"
    echo
    failures=1
  fi
done

if [[ "$failures" -ne 0 ]]; then
  echo "copy-quality: FAILED"
  exit 1
fi

echo "copy-quality: PASSED"
