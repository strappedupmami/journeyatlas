# Atlas Concierge Runbook

## 1) Run CLI
From workspace root (`atlas-concierge`):

```bash
cargo run -p atlas-cli -- chat
```

Other commands:

```bash
cargo run -p atlas-cli -- plan-trip --style beach --days 2 --locale he
cargo run -p atlas-cli -- ops checklist turnover
cargo run -p atlas-cli -- kb search "מים אפורים" --limit 5
```

## 2) Run Server (Axum API)

```bash
cp .env.example .env
export $(grep -v '^#' .env | xargs)
cargo run -p atlas-api
```

Health check:

```bash
curl http://localhost:8080/health
```

Chat request:

```bash
curl -X POST http://localhost:8080/v1/chat \
  -H "content-type: application/json" \
  -H "x-api-key: dev-atlas-key" \
  -d '{"text":"תכנן לי סופ\"ש חופים"}'
```

Browser UI option (from website static files):
- Serve homepage over HTTP (cookies will not work on `file://`):

```bash
cd /Users/avrohom/Downloads/journeyatlas
./scripts/serve-homepage-local.sh
```

- Open `http://localhost:5500/concierge-local.html`
- Keep API base `http://localhost:8080` and API key `dev-atlas-key`
- Use buttons for login (Google + Passkey), profile save, `/v1/chat`, `/v1/plan_trip`

Plan trip:

```bash
curl -X POST http://localhost:8080/v1/plan_trip \
  -H "content-type: application/json" \
  -H "x-api-key: dev-atlas-key" \
  -d '{"style":"beach","days":3,"locale":"he","constraints":[]}'
```

Legacy local cookie login example (debug only):

```bash
curl -i -c cookies.txt -X POST http://localhost:8080/v1/auth/social_login \
  -H "content-type: application/json" \
  -H "x-api-key: dev-atlas-key" \
  -d '{"provider":"google","email":"demo@atlasmasa.com","name":"Demo User","locale":"he"}'
```

Read signed-in user from cookie:

```bash
curl -b cookies.txt http://localhost:8080/v1/auth/me \
  -H "x-api-key: dev-atlas-key"
```

## 3) Add Knowledge Base Docs
1. Add markdown files under:
- `kb/faq/`
- `kb/policies/`
- `kb/guides/`
- `kb/ops/`
2. Restart CLI/API process (current retriever loads docs at startup).
3. Validate retrieval via:

```bash
cargo run -p atlas-cli -- kb search "שאילתא" --limit 5
```

## 4) Burn ML Mode / Model Swaps
Current architecture is hybrid:
- Rules + retrieval always work.
- ML augments intent/ranking.

Default intent training dataset:
- `kb/training/intent_he.jsonl`

To train centroid classifier from Hebrew dataset:

```bash
export ATLAS_INTENT_DATASET=kb/training/intent_he.jsonl
cargo run -p atlas-cli -- chat
```

Enable Burn components:

```bash
cargo run -p atlas-cli --features atlas-ml/burn-ml -- chat
```

For ONNX-import path:
1. Convert ONNX with Burn import tooling into Rust module (outside this baseline).
2. Replace `crates/ml/src/burn_impl.rs` embed/classifier implementation with generated module calls.
3. Keep fallback path intact for unsupported ONNX operators.

Notes:
- Burn ONNX support and operator coverage are evolving.
- Keep `HashEmbeddingModel` fallback available for reliability.

## 4.1) Hebrew Research Refresh Workflow
1. Refresh cached Hebrew sources:

```bash
./scripts/refresh_hebrew_sources.sh
```

2. Review cached pages under:
- `docs/source-cache/hebrew/`

3. Update structured files:
- `kb/research/hebrew-web-sources-2026-02-14.md`
- `kb/research/israel-rv-service-points-he.json`
- `kb/research/rv-service-points-he.md`

## 5) Tests and Quality

```bash
cargo test -p atlas-core
cargo test -p atlas-tests
cargo clippy --workspace --all-targets -- -D warnings
```

If a full workspace build is needed:

```bash
cargo build --workspace
```

## 6) Security Defaults
- API key required on `/v1/*` endpoints.
- Per-IP in-memory rate limiting.
- 64KB request size limit.
- Structured JSON logs with request IDs.
- Secure cookie support (`ATLAS_COOKIE_SECURE=true`) with optional shared domain (`ATLAS_SESSION_COOKIE_DOMAIN=.atlasmasa.com`).
- Tight same-site cookie policy (`ATLAS_COOKIE_SAMESITE=strict` in production).
- OAuth state verification + PKCE for Google sign-in (`/v1/auth/google/start`, `/v1/auth/google/callback`).
- Passkey (WebAuthn) endpoints:
  - `POST /v1/auth/passkey/register/start`
  - `POST /v1/auth/passkey/register/finish`
  - `POST /v1/auth/passkey/login/start`
  - `POST /v1/auth/passkey/login/finish`
- Long-term memory import endpoint:
  - `POST /v1/memory/import`
- Stripe checkout webhook endpoint with signature validation:
  - `POST /v1/billing/stripe_webhook`

## 7) Persistence Modes
- Default: in-memory store (fast local development).
- SQLite mode:

```bash
export ATLAS_DATABASE_URL=sqlite://atlas_concierge.db
cargo run -p atlas-api
```

Session memory uses TTL (24h default) and supports purge via agent method.

## 8) Production Provider Setup (api.atlasmasa.com)
1. Google OAuth:
   - Create OAuth Web app in Google Cloud Console.
   - Authorized redirect URI: `https://api.atlasmasa.com/v1/auth/google/callback`
   - Authorized JS origin: `https://atlasmasa.com`
   - Fill `ATLAS_GOOGLE_CLIENT_ID`, `ATLAS_GOOGLE_CLIENT_SECRET`, `ATLAS_GOOGLE_REDIRECT_URI`.
2. Passkeys/WebAuthn:
   - Set `ATLAS_WEBAUTHN_RP_ID=atlasmasa.com`
   - Set `ATLAS_WEBAUTHN_ORIGIN=https://atlasmasa.com`
   - Use HTTPS only (`ATLAS_COOKIE_SECURE=true`).
3. Stripe monthly subscription (Apple Pay capable):
   - Create monthly recurring price in Stripe and copy `price_...` to `ATLAS_STRIPE_MONTHLY_PRICE_ID`.
   - Set webhook to `https://api.atlasmasa.com/v1/billing/stripe_webhook`.
   - Configure `ATLAS_STRIPE_SECRET_KEY` + `ATLAS_STRIPE_WEBHOOK_SECRET`.
   - In Stripe dashboard, verify domain for Apple Pay.
4. OpenAI premium runtime:
   - Set `ATLAS_OPENAI_API_KEY`.
   - Keep `ATLAS_OPENAI_MODEL=gpt-5.2` and `ATLAS_OPENAI_REASONING_EFFORT=high` (or adjust to available production model).
