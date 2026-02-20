#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/atlas-concierge"

export ATLAS_API_KEY="${ATLAS_API_KEY:-dev-atlas-key}"
export ATLAS_BIND="${ATLAS_BIND:-0.0.0.0:8080}"
export ATLAS_KB_ROOT="${ATLAS_KB_ROOT:-kb}"
export ATLAS_COOKIE_SECURE="${ATLAS_COOKIE_SECURE:-false}"
export ATLAS_COOKIE_SAMESITE="${ATLAS_COOKIE_SAMESITE:-lax}"
export ATLAS_ALLOW_LEGACY_SOCIAL_LOGIN="${ATLAS_ALLOW_LEGACY_SOCIAL_LOGIN:-true}"
export ATLAS_FRONTEND_ORIGIN="${ATLAS_FRONTEND_ORIGIN:-http://localhost:5500}"
export ATLAS_GOOGLE_REDIRECT_URI="${ATLAS_GOOGLE_REDIRECT_URI:-http://localhost:8080/v1/auth/google/callback}"
export ATLAS_WEBAUTHN_RP_ID="${ATLAS_WEBAUTHN_RP_ID:-localhost}"
export ATLAS_WEBAUTHN_ORIGIN="${ATLAS_WEBAUTHN_ORIGIN:-http://localhost:5500}"
export ATLAS_ALLOWED_ORIGINS="${ATLAS_ALLOWED_ORIGINS:-http://localhost:5500,http://127.0.0.1:5500}"

printf "\n[Atlas Concierge] Starting API on %s with kb=%s\n" "$ATLAS_BIND" "$ATLAS_KB_ROOT"
printf "API Key: %s\n" "$ATLAS_API_KEY"
printf "Cookie secure: %s\n" "$ATLAS_COOKIE_SECURE"
printf "Open UI: %s\n\n" "$ROOT_DIR/website/concierge-local.html"

cargo run -p atlas-api
