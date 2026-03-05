#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

STRICT="${ATLAS_QUALITY_STRICT:-0}"
LOCKFILE_MODE="${ATLAS_QUALITY_LOCKFILE_MODE:-sync-check}"
skipped=()

run_check() {
  local label="$1"
  shift
  printf "\n==> %s\n" "$label"
  "$@"
}

run_check "Policy guard: lockfiles (${LOCKFILE_MODE})" ./scripts/verify-lockfiles.sh "$LOCKFILE_MODE"
run_check "Policy guard: actions pinning" ./scripts/verify-github-actions-pinning.sh
run_check "Policy guard: workflow trust boundaries" ./scripts/verify-workflow-trust-boundaries.sh
run_check "Policy guard: dependency PR scope" ./scripts/verify-dependency-pr-scope.sh
run_check "Product copy quality" ./scripts/verify-product-copy-quality.sh

run_check "Web lint" npm run lint
run_check "Web typecheck" npm run typecheck
run_check "Web production build" npm run build

run_check "Rust format" bash -lc 'cd atlas-concierge && cargo fmt --all --check'
run_check "Rust lint" bash -lc 'cd atlas-concierge && cargo clippy --workspace --all-targets -- -D warnings'
run_check "Rust tests" bash -lc 'cd atlas-concierge && cargo test -p atlas-tests --locked'

if command -v xcrun >/dev/null 2>&1; then
  run_check "Swift syntax parse (iOS + macOS)" bash -lc '
    set -euo pipefail
    while IFS= read -r file; do
      xcrun swiftc -parse "$file"
    done < <(find ios-app/AtlasMasaIOS/Sources macos-app/AtlasMasaMacOS/Sources -name "*.swift" | sort)
  '
else
  skipped+=("swift_parse:xcrun_not_found")
fi

if [[ -x "android-app/gradlew" ]]; then
  run_check "Android unit tests" bash -lc 'cd android-app && ./gradlew --no-daemon :app:testDebugUnitTest'
  run_check "Android lint" bash -lc 'cd android-app && ./gradlew --no-daemon :app:lintDebug'
else
  skipped+=("android_checks:gradlew_missing")
fi

if command -v dotnet >/dev/null 2>&1; then
  run_check "Windows build (warnings as errors)" dotnet build windows-app/AtlasMasaWindows/AtlasMasaWindows.csproj -warnaserror
else
  skipped+=("windows_checks:dotnet_not_found")
fi

if [[ "${#skipped[@]}" -gt 0 ]]; then
  printf "\nSkipped checks:\n"
  printf ' - %s\n' "${skipped[@]}"
  if [[ "$STRICT" == "1" ]]; then
    echo "quality-gate: FAILED (strict mode blocks skipped checks)"
    exit 1
  fi
fi

printf "\nquality-gate: PASSED\n"
