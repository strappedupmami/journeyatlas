# Atlas/אטלס Release Readiness Report

Date: 2026-02-21
Repository: `/Users/avrohom/Downloads/journeyatlas`
Scope: final production hardening pass for auth/session/OAuth/passkey/billing/memory privacy/mobile UX/feedback/security workflows.

## Executive status

Release status: **Conditional Go**.

The codebase now has strict passwordless auth paths, hardened webhook verification, first-party origin-based API access for browser clients, stronger feedback sanitization, and passing Rust + web checks.

Remaining go-live blockers are operational (dashboard + DNS + provider credentials), not code defects.

## What was hardened in this pass

### 1) Auth + OAuth + passkey surfaces
- Kept passwordless-only posture and legacy login retirement.
- Tightened API-key middleware to allow first-party browser requests by trusted origin while preserving server-to-server key auth.
- Added explicit unauthorized messaging for missing key/untrusted origin.

Primary files:
- `/Users/avrohom/Downloads/journeyatlas/atlas-concierge/crates/api/src/lib.rs`
- `/Users/avrohom/Downloads/journeyatlas/atlas-concierge/crates/tests/tests/api_integration.rs`

### 2) Session, CSRF, and cookie hardening
- Preserved strict cookie behavior (`HttpOnly`, `Secure`, `SameSite`, domain-scoped).
- Preserved CSRF origin enforcement for cookie-authenticated state-changing requests.
- Added/kept abuse tests for auth endpoint throttling and cross-origin protection.

Primary files:
- `/Users/avrohom/Downloads/journeyatlas/atlas-concierge/crates/api/src/lib.rs`
- `/Users/avrohom/Downloads/journeyatlas/atlas-concierge/crates/tests/tests/api_integration.rs`

### 3) Billing/webhook hardening
- Strengthened Stripe webhook signature verification:
  - timestamp tolerance enforcement
  - replay-window rejection
  - support for multiple signatures
  - oversized payload rejection
- Added tests for valid/replay signature behavior.

Primary files:
- `/Users/avrohom/Downloads/journeyatlas/atlas-concierge/crates/api/src/lib.rs`

### 4) Memory privacy/security
- Privacy and memory behavior remain guarded by opt-in controls and tests already in place.
- Existing memory tests pass (ingestion, ordering, privacy opt-out).

Primary files:
- `/Users/avrohom/Downloads/journeyatlas/atlas-concierge/crates/api/src/lib.rs`

### 5) Feedback/reporting with negative-signal path
- Improved auto-report flow to reduce noisy abuse:
  - per-session report cap
  - cooldown interval
- Tightened feedback payload sanitization and bounds checks (message/tags/source/category).

Primary files:
- `/Users/avrohom/Downloads/journeyatlas/website/concierge-local.html`
- `/Users/avrohom/Downloads/journeyatlas/atlas-concierge/crates/api/src/lib.rs`

### 6) Mobile/web UX and build reliability
- Removed dependency on remote Google Fonts at build-time for deterministic builds in restricted/offline environments.
- Fixed lint issue in Hebrew quoted text.

Primary files:
- `/Users/avrohom/Downloads/journeyatlas/app/layout.tsx`
- `/Users/avrohom/Downloads/journeyatlas/app/globals.css`
- `/Users/avrohom/Downloads/journeyatlas/app/packages/page.tsx`

### 7) CI + security workflow guardrails
- CI web job now includes production build step.
- Security workflow and dependency/audit workflow continue enforcing policy, secret scanning, SAST, and audits.

Primary files:
- `/Users/avrohom/Downloads/journeyatlas/.github/workflows/ci.yml`
- `/Users/avrohom/Downloads/journeyatlas/.github/workflows/security-scan.yml`

## Checks run in this pass

### Web
- `npm run lint` ✅
- `npm run typecheck` ✅
- `npm run build` ✅

### Rust
- `cargo fmt --all --check` ✅
- `cargo clippy --workspace --all-targets -- -D warnings` ✅
- `cargo test -p atlas-tests --locked` ✅
- `cargo test -p atlas-api --locked` ✅

## Exact environment variables you must set (production API)

Set these in Railway service variables for the API service:

### Core runtime
- `ATLAS_BIND=0.0.0.0:8080`
- `ATLAS_KB_ROOT=kb`
- `ATLAS_DATABASE_URL=<railway-persistent-sqlite-or-postgres-url>`
- `ATLAS_ALLOWED_ORIGINS=https://atlasmasa.com,https://www.atlasmasa.com`
- `ATLAS_FRONTEND_ORIGIN=https://atlasmasa.com`

### API auth + rate limiting
- `ATLAS_API_KEY=<strong-random-key>`
- `ATLAS_API_RATE_LIMIT_WINDOW_SECONDS=60`
- `ATLAS_API_RATE_LIMIT_MAX=80`
- `ATLAS_AUTH_RATE_LIMIT_WINDOW_SECONDS=60`
- `ATLAS_AUTH_RATE_LIMIT_MAX=12`

### Session and cookie
- `ATLAS_SESSION_TTL_SECONDS=2592000`
- `ATLAS_SESSION_COOKIE_NAME=atlas_session`
- `ATLAS_SESSION_COOKIE_DOMAIN=.atlasmasa.com`
- `ATLAS_COOKIE_SAMESITE=strict`

### Google OAuth
- `ATLAS_GOOGLE_CLIENT_ID=<from Google Cloud OAuth client>`
- `ATLAS_GOOGLE_CLIENT_SECRET=<from Google Cloud OAuth client>`
- `ATLAS_GOOGLE_REDIRECT_URI=https://api.atlasmasa.com/v1/auth/google/callback`

### Apple Sign In (web)
- `ATLAS_APPLE_CLIENT_ID=com.atlasmasa.web` (or your final Services ID)
- `ATLAS_APPLE_CLIENT_SECRET=<Apple client secret JWT>`
- `ATLAS_APPLE_REDIRECT_URI=https://api.atlasmasa.com/v1/auth/apple/callback`

### WebAuthn/passkey
- `ATLAS_WEBAUTHN_RP_ID=atlasmasa.com`
- `ATLAS_WEBAUTHN_ORIGIN=https://atlasmasa.com`
- `ATLAS_WEBAUTHN_RP_NAME=Atlas/אטלס`

### Billing/Stripe
- `ATLAS_STRIPE_SECRET_KEY=<stripe secret>`
- `ATLAS_STRIPE_WEBHOOK_SECRET=<stripe webhook signing secret>`
- `ATLAS_STRIPE_WEBHOOK_TOLERANCE_SECONDS=300`
- `ATLAS_STRIPE_MONTHLY_PRICE_ID=<price_xxx>`
- `ATLAS_STRIPE_SUCCESS_URL=https://atlasmasa.com/concierge-local.html?billing=success`
- `ATLAS_STRIPE_CANCEL_URL=https://atlasmasa.com/concierge-local.html?billing=cancel`
- `ATLAS_STRIPE_RETURN_URL=https://atlasmasa.com/concierge-local.html?billing=portal`
- `ATLAS_SUBSCRIPTION_BYPASS_EMAILS=ceo@atlasmasa.com`

### AI runtime
- `ATLAS_OPENAI_API_KEY=<openai key>`
- `ATLAS_OPENAI_MODEL=gpt-5.2`
- `ATLAS_OPENAI_REASONING_EFFORT=high`

## Dashboard actions you must complete

### 1) Railway (API service)
1. Open the API service in Railway (root directory `atlas-concierge`).
2. Confirm deploy is healthy at `https://<railway-domain>/health`.
3. Add all env vars listed above.
4. Add persistent volume mounted at `/data` if you want local durable SQLite-style data survival across restarts.
5. Attach custom domain `api.atlasmasa.com` to this API service only.

### 2) DNS
1. In your DNS provider, create `CNAME` for `api` pointing to the Railway public hostname for API.
2. Wait for validation until `https://api.atlasmasa.com/health` returns 200.

### 3) Apple Developer + Services ID
1. Keep Services ID configured for web sign-in (`com.atlasmasa.web` or final ID).
2. In Services ID web config, set:
   - Domain: `atlasmasa.com`
   - Return URL: `https://api.atlasmasa.com/v1/auth/apple/callback`
3. Generate and rotate Apple client secret JWT before expiry.
4. Put that JWT in `ATLAS_APPLE_CLIENT_SECRET`.

### 4) Google Cloud OAuth
1. Add Authorized JS origins:
   - `https://atlasmasa.com`
   - `https://www.atlasmasa.com`
2. Add Redirect URI:
   - `https://api.atlasmasa.com/v1/auth/google/callback`
3. Publish consent screen and include production domain links.
4. Copy client ID/secret into Railway env vars.

### 5) Stripe + Apple Pay
1. Create monthly recurring price; copy `price_...` into env var.
2. Create webhook endpoint:
   - `https://api.atlasmasa.com/v1/billing/stripe_webhook`
3. Subscribe webhook events:
   - `checkout.session.completed`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
4. Verify Apple Pay domain in Stripe dashboard for `atlasmasa.com`.

### 6) Vercel (website)
1. Set frontend origin/API base to point at `https://api.atlasmasa.com`.
2. Redeploy production once API domain is healthy.

### 7) GitHub repository security
1. Enforce branch protection on `main` (+ `production` if used).
2. Require signed commits and required checks.
3. Keep secret scanning + push protection enabled.

## Remaining known risks / final gate checks

- If `api.atlasmasa.com` DNS is not validated, passkey/OAuth will fail even though code is ready.
- If OAuth provider credentials are missing or mismatch redirect URLs, sign-in callbacks fail.
- If Stripe webhook secret is missing, subscription state will not sync reliably.
- If `ATLAS_DATABASE_URL` points to ephemeral storage, long-term personalization will not survive restarts.

## Go-live verification script (manual)

1. `curl -i https://api.atlasmasa.com/health` -> must be `200`.
2. Browser test on `https://atlasmasa.com`:
   - Apple sign-in success and user appears authenticated.
   - Google sign-in success and user appears authenticated.
   - Passkey enroll + passkey sign-in success.
3. Trigger Stripe checkout and confirm webhook updates account subscription status.
4. Submit feedback and verify anonymized auto-report path only triggers by user confirmation.
5. Confirm cookies are secure in devtools:
   - `HttpOnly`, `Secure`, `SameSite=Strict`, domain `.atlasmasa.com`.

## Notes on repository cleanliness

This pass committed only hardening/release files. Your workspace currently contains additional pre-existing iOS/macOS local changes and untracked project artifacts outside this scope; those should be reviewed separately before a fully clean tree is possible.
