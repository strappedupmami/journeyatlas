#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Generate Sign in with Apple client secret JWT (ES256).

Required:
  --team-id <APPLE_TEAM_ID>
  --key-id <APPLE_KEY_ID>
  --client-id <APPLE_SERVICES_ID>   (example: com.atlasmasa.web)
  --p8 <path-to-AuthKey_XXXX.p8>

Optional:
  --ttl-seconds <seconds>           default: 15552000 (180 days)
  --copy                            copy JWT to clipboard (macOS pbcopy)

Example:
  scripts/generate-apple-client-secret.sh \
    --team-id BW93SGS88H \
    --key-id ABC123DEF4 \
    --client-id com.atlasmasa.web \
    --p8 "$HOME/Downloads/AuthKey_ABC123DEF4.p8" \
    --copy
EOF
}

b64url() {
  openssl base64 -e -A | tr '+/' '-_' | tr -d '='
}

TEAM_ID=""
KEY_ID=""
CLIENT_ID=""
P8_PATH=""
TTL_SECONDS="15552000"
COPY_TO_CLIPBOARD="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --team-id)
      TEAM_ID="${2:-}"
      shift 2
      ;;
    --key-id)
      KEY_ID="${2:-}"
      shift 2
      ;;
    --client-id)
      CLIENT_ID="${2:-}"
      shift 2
      ;;
    --p8)
      P8_PATH="${2:-}"
      shift 2
      ;;
    --ttl-seconds)
      TTL_SECONDS="${2:-}"
      shift 2
      ;;
    --copy)
      COPY_TO_CLIPBOARD="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$TEAM_ID" || -z "$KEY_ID" || -z "$CLIENT_ID" || -z "$P8_PATH" ]]; then
  echo "Missing required arguments." >&2
  usage
  exit 1
fi

if ! [[ "$TTL_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "--ttl-seconds must be an integer (seconds)." >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required." >&2
  exit 1
fi

if [[ ! -f "$P8_PATH" ]]; then
  echo "p8 file not found: $P8_PATH" >&2
  exit 1
fi

NOW="$(date +%s)"
EXP="$((NOW + TTL_SECONDS))"

HEADER_B64="$(printf '{"alg":"ES256","kid":"%s"}' "$KEY_ID" | b64url)"
PAYLOAD_B64="$(printf '{"iss":"%s","iat":%s,"exp":%s,"aud":"https://appleid.apple.com","sub":"%s"}' "$TEAM_ID" "$NOW" "$EXP" "$CLIENT_ID" | b64url)"
UNSIGNED="${HEADER_B64}.${PAYLOAD_B64}"
SIG_B64="$(printf '%s' "$UNSIGNED" | openssl dgst -binary -sha256 -sign "$P8_PATH" | b64url)"
JWT="${UNSIGNED}.${SIG_B64}"

# Sanity check: JWT must be exactly three dot-separated segments.
DOT_COUNT="$(printf '%s' "$JWT" | tr -cd '.' | wc -c | tr -d ' ')"
if [[ "$DOT_COUNT" != "2" ]]; then
  echo "Generated token does not look like a valid JWT (dot count: $DOT_COUNT)." >&2
  exit 1
fi

if [[ "$COPY_TO_CLIPBOARD" == "true" ]]; then
  if command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$JWT" | pbcopy
    echo "JWT copied to clipboard."
  else
    echo "pbcopy not available; printing JWT to stdout instead." >&2
    printf '%s\n' "$JWT"
  fi
else
  printf '%s\n' "$JWT"
fi

