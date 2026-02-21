# Apple Sign-In for Website (Atlas/אטלס)

This guide enables Sign in with Apple for `https://atlasmasa.com` against the Rust API.

## 1) Verify backend routes exist
The API already exposes:
- `GET /v1/auth/apple/start`
- `GET /v1/auth/apple/callback`

Website button trigger exists in:
- `/Users/avrohom/Downloads/journeyatlas/website/concierge-local.html`

## 2) Apple Developer prerequisites
- App ID (iOS): `com.atlasmasa.ios` with `Sign in with Apple`.
- App ID (macOS): `com.atlasmasa.macos` with `Sign in with Apple`.
- Services ID (web): `com.atlasmasa.web` with `Sign in with Apple`.
- Services ID config:
  - Domain: `atlasmasa.com`
  - Return URL (prod): `https://api.atlasmasa.com/v1/auth/apple/callback`
  - Temporary return URL (before custom API domain): `https://journeyatlas-production.up.railway.app/v1/auth/apple/callback`
- Key: Sign in with Apple key (`.p8`).

## 3) Generate Apple client secret JWT
Use:

```bash
cd /Users/avrohom/Downloads/journeyatlas
scripts/generate-apple-client-secret.sh \
  --team-id BW93SGS88H \
  --key-id <YOUR_KEY_ID> \
  --client-id com.atlasmasa.web \
  --p8 "$HOME/Downloads/AuthKey_<YOUR_KEY_ID>.p8" \
  --copy
```

This copies JWT to clipboard for secure paste into Railway.

## 4) Set Railway API service variables
In Railway -> API service (`journeyatlas`) -> Variables:
- `ATLAS_APPLE_CLIENT_ID=com.atlasmasa.web`
- `ATLAS_APPLE_CLIENT_SECRET=<paste JWT>`
- `ATLAS_APPLE_REDIRECT_URI=https://journeyatlas-production.up.railway.app/v1/auth/apple/callback`
- `ATLAS_FRONTEND_ORIGIN=https://atlasmasa.com`

Do not set `ATLAS_BIND` unless explicitly needed.

## 5) Redeploy and verify capability gate

```bash
curl -s https://journeyatlas-production.up.railway.app/health
```

Expected:
- `"apple_oauth": true`

## 6) End-to-end test
1. Open `https://atlasmasa.com/concierge-local.html?api_base=https%3A%2F%2Fjourneyatlas-production.up.railway.app`
2. Click `Sign in with Apple`.
3. Complete Apple flow.
4. Confirm redirect back with `?auth=success`.
5. Confirm authenticated session by calling `/v1/auth/me` from UI flow.

## 7) Finalize custom API domain
After `api.atlasmasa.com` is live:
- Update Services ID return URL to `https://api.atlasmasa.com/v1/auth/apple/callback`.
- Update Railway:
  - `ATLAS_APPLE_REDIRECT_URI=https://api.atlasmasa.com/v1/auth/apple/callback`
- Redeploy API.
