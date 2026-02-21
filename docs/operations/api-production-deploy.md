# Atlas/אטלס API Production Deploy (api.atlasmasa.com)

This checklist hardens the Rust API for production deployment with Google OAuth, Apple OAuth, passkeys, and monthly subscriptions.

## 1) Infrastructure
- Deploy `atlas-concierge` API as its own service (Docker image from `atlas-concierge/Dockerfile`).
- Terminate TLS at your edge/load balancer and forward to API on `:8080`.
- Point `api.atlasmasa.com` to the service.

### Railway-specific setup (recommended)
- In Railway, create a **separate API service** from this repo.
- Service root directory must be: `atlas-concierge`
- Builder: Dockerfile (auto-detected from `atlas-concierge/Dockerfile`)
- Keep Vercel website deploy separate from Railway API deploy.
- Do **not** set `ATLAS_BIND` unless you explicitly need to override binding behavior.
  - API auto-binds to Railway `PORT` by default.

## 2) Required environment variables
Use `atlas-concierge/.env.example` as source of truth. In production, set at least:
- `ATLAS_API_KEY`
- `ATLAS_DATABASE_URL`
- `ATLAS_COOKIE_SAMESITE=strict`
- `ATLAS_SESSION_COOKIE_DOMAIN=atlasmasa.com`
- `ATLAS_ALLOWED_ORIGINS=https://atlasmasa.com,https://www.atlasmasa.com`
- `ATLAS_FRONTEND_ORIGIN=https://atlasmasa.com`
- `ATLAS_API_RATE_LIMIT_WINDOW_SECONDS=60`
- `ATLAS_API_RATE_LIMIT_MAX=80`
- `ATLAS_AUTH_RATE_LIMIT_WINDOW_SECONDS=60`
- `ATLAS_AUTH_RATE_LIMIT_MAX=12`
- `ATLAS_GOOGLE_CLIENT_ID`
- `ATLAS_GOOGLE_CLIENT_SECRET`
- `ATLAS_GOOGLE_REDIRECT_URI=https://api.atlasmasa.com/v1/auth/google/callback`
- `ATLAS_APPLE_CLIENT_ID` (Services ID, example: `com.atlasmasa.web`)
- `ATLAS_APPLE_CLIENT_SECRET` (JWT signed with Apple `.p8` key)
- `ATLAS_APPLE_REDIRECT_URI=https://api.atlasmasa.com/v1/auth/apple/callback`
- `ATLAS_WEBAUTHN_RP_ID=atlasmasa.com`
- `ATLAS_WEBAUTHN_ORIGIN=https://atlasmasa.com`
- `ATLAS_STRIPE_SECRET_KEY`
- `ATLAS_STRIPE_WEBHOOK_SECRET`
- `ATLAS_STRIPE_WEBHOOK_TOLERANCE_SECONDS=300`
- `ATLAS_STRIPE_MONTHLY_PRICE_ID`
- `ATLAS_OPENAI_API_KEY`

Notes:
- `ATLAS_API_KEY` is still required for server-to-server clients.
- First-party browser traffic from `ATLAS_ALLOWED_ORIGINS` is accepted without exposing this key in frontend source.

## 3) Google OAuth console setup
In Google Cloud Console:
- OAuth client type: Web application.
- Authorized JavaScript origins:
  - `https://atlasmasa.com`
  - `https://www.atlasmasa.com`
- Authorized redirect URIs:
  - `https://api.atlasmasa.com/v1/auth/google/callback`
- Publish OAuth consent screen (External) and add production domain:
  - `atlasmasa.com`
  - `api.atlasmasa.com`
- Add support email + privacy policy URL + terms URL.
- Add scopes:
  - `openid`
  - `email`
  - `profile`
- Create production client credentials and store only in runtime secrets manager.

## 4) Passkey/WebAuthn setup
- Ensure origin + RP ID are exact:
  - RP ID: `atlasmasa.com`
  - Origin: `https://atlasmasa.com`
- Passkeys require HTTPS in production and valid certificate chain.

## 4.1) Apple OAuth setup (website)
In Apple Developer:
- Create App IDs for iOS/macOS with `Sign in with Apple` enabled.
- Create a Services ID for web (example: `com.atlasmasa.web`) with `Sign in with Apple`.
- Configure Services ID domain + return URL:
  - Domain: `atlasmasa.com`
  - Return URL: `https://api.atlasmasa.com/v1/auth/apple/callback`
- Create a Sign in with Apple key (`.p8`) and associate with primary App ID.

Generate `ATLAS_APPLE_CLIENT_SECRET` (JWT):
- Use `/Users/avrohom/Downloads/journeyatlas/scripts/generate-apple-client-secret.sh`
- Example:
  - `scripts/generate-apple-client-secret.sh --team-id <TEAM_ID> --key-id <KEY_ID> --client-id com.atlasmasa.web --p8 /path/to/AuthKey_<KEY_ID>.p8 --copy`

## 5) Stripe monthly subscription + Apple Pay
In Stripe:
- Create recurring monthly price and set `ATLAS_STRIPE_MONTHLY_PRICE_ID`.
- Add webhook endpoint:
  - `https://api.atlasmasa.com/v1/billing/stripe_webhook`
  - Subscribe to:
    - `checkout.session.completed`
    - `customer.subscription.updated`
    - `customer.subscription.deleted`
- Verify domain for Apple Pay in Stripe dashboard for live mode.

## 6) OpenAI premium runtime
- Set `ATLAS_OPENAI_API_KEY`.
- Default model/reasoning is configured as:
  - `ATLAS_OPENAI_MODEL=gpt-5.2`
  - `ATLAS_OPENAI_REASONING_EFFORT=high`
- If model availability differs in your account, adjust env var without code changes.

## 7) Security baseline verification
- Confirm all auth cookies are `HttpOnly`, `Secure`, `SameSite`, and domain-scoped to `atlasmasa.com`.
- Confirm CORS only allows your production domains.
- Confirm CSRF origin checks are enforced for cookie-authenticated write requests.
- Confirm auth start/finish endpoints are rate-limited (`auth_rate_limited` on abuse).
- Confirm webhook signature validation is enabled (`ATLAS_STRIPE_WEBHOOK_SECRET` set).
- Confirm legacy auth route is retired:
  - `POST /v1/auth/social_login` returns `410 legacy_auth_retired`
- Confirm branch protections and code security settings are enabled (see `/Users/avrohom/Downloads/journeyatlas/docs/security/repository-hardening.md`).

## 8) Explicit owner actions required (cannot be automated by code edits)
- In Google Cloud, create/own the OAuth app and provide:
  - `ATLAS_GOOGLE_CLIENT_ID`
  - `ATLAS_GOOGLE_CLIENT_SECRET`
- In Stripe dashboard, create live monthly price and Apple Pay domain verification.
- In deployment platform, set all API env vars for `api.atlasmasa.com`.
- In GitHub repo settings, enforce signed commits + branch protections.
