# Atlas Masa Production Gap Checklist

Last updated: 2026-02-20
Owner: Principal Engineering (execution run)

## Audit contract
This checklist audits production readiness against the contract:
- Rust-first backend
- Passwordless-only auth (Google OAuth, Passkey, Apple Sign In)
- Monthly Stripe subscription (Apple Pay-capable checkout)
- Deep long-term personalization (notes, survey, memory, proactive feed)
- Mobile-first UX + stable language switcher in hamburger menu
- Security hardening for API, sessions, OAuth, billing webhook, and repo CI

## Severity rubric
- `P0`: breakage/security risk blocking production behavior now
- `P1`: high-value hardening not blocking core prod operation today
- `P2`: quality/operational improvement

## Gap register

### G-001: Multi-base API failover was not resilient (caused 502 dead UX)
- Severity: `P0`
- Status: `Closed`
- Contract area: Mobile-first UX, auth/survey reliability
- Evidence: Studio showed `Connection issue: 502`, `Passkey login start failed (502)`, `Could not load survey` while API candidates existed.
- Exact files:
  - `/Users/avrohom/Downloads/journeyatlas/website/concierge-local.html`
- Implementation plan executed:
  1. Harden request client to continue across API base candidates on upstream failures.
  2. Prefer `https://api.atlasmasa.com` first on production domains.
  3. Return structured failure telemetry after all candidates fail.
- Acceptance criteria:
  - If one upstream returns `5xx`, client retries alternate candidates automatically.
  - Passkey/survey requests do not dead-end on first failing base.
  - Debug payload includes failed candidate list.

### G-002: Passwordless-only policy not enforced by default
- Severity: `P0`
- Status: `Closed`
- Contract area: Passwordless auth + security hardening
- Exact files:
  - `/Users/avrohom/Downloads/journeyatlas/atlas-concierge/crates/api/src/lib.rs`
  - `/Users/avrohom/Downloads/journeyatlas/atlas-concierge/crates/tests/tests/api_integration.rs`
- Implementation plan executed:
  1. Set legacy `/v1/auth/social_login` fallback default to disabled.
  2. Keep explicit env switch for controlled local/test usage.
  3. Update tests to explicitly enable legacy fallback only in test scope.
- Acceptance criteria:
  - Production default does not allow password-based/legacy social shortcut flows.
  - Google/Apple OAuth + Passkey remain primary passwordless paths.

### G-003: Apple Sign In endpoint pair missing from auth stack
- Severity: `P0`
- Status: `Closed`
- Contract area: Passwordless auth completeness
- Exact files:
  - `/Users/avrohom/Downloads/journeyatlas/atlas-concierge/crates/api/src/lib.rs`
  - `/Users/avrohom/Downloads/journeyatlas/website/concierge-local.html`
- Implementation plan executed:
  1. Add Apple OAuth runtime config loader.
  2. Add `/v1/auth/apple/start` and `/v1/auth/apple/callback` handlers.
  3. Add Apple button and frontend launch flow.
  4. Wire OAuth state validation (provider/state/nonce/expiry) and session issuance.
- Acceptance criteria:
  - Apple sign-in button launches OAuth flow from Studio.
  - Callback issues Atlas session cookie and redirects to Studio.
  - Misconfigured provider returns explicit service-unavailable response.

### G-004: OAuth/public endpoint policy + health capability signaling incomplete
- Severity: `P0`
- Status: `Closed`
- Contract area: API security and operability
- Exact files:
  - `/Users/avrohom/Downloads/journeyatlas/atlas-concierge/crates/api/src/lib.rs`
  - `/Users/avrohom/Downloads/journeyatlas/website/concierge-local.html`
- Implementation plan executed:
  1. Expand `/health` with capability flags (`google_oauth`, `apple_oauth`, `passkey`, `billing`).
  2. Ensure Apple auth routes are treated as public where required.
  3. Gate UI actions by capabilities to prevent dead buttons.
- Acceptance criteria:
  - Studio disables unavailable auth/billing actions with clear reason.
  - `/health` returns capability map used by UI to drive safe behavior.

### G-005: Survey became non-functional during API degradation
- Severity: `P0`
- Status: `Closed`
- Contract area: Deep personalization continuity
- Exact files:
  - `/Users/avrohom/Downloads/journeyatlas/website/concierge-local.html`
- Implementation plan executed:
  1. Add local adaptive survey fallback payload generation.
  2. Preserve user progression in local mode until API recovers.
  3. Provide explicit output explaining temporary fallback mode.
- Acceptance criteria:
  - Survey panel remains functional when `/v1/survey/next` fails.
  - User can still progress through core survey questions.
  - UX communicates local fallback clearly.

### G-006: Language switcher placement unstable for mobile navigation expectations
- Severity: `P0`
- Status: `Closed`
- Contract area: Mobile-first UX
- Exact files:
  - `/Users/avrohom/Downloads/journeyatlas/website/sitewide-language.js`
- Implementation plan executed:
  1. Make switcher mount responsive to viewport changes.
  2. Keep switcher inside hamburger menu on mobile widths.
  3. Keep desktop/header fallback when not mobile.
- Acceptance criteria:
  - On mobile widths, language switcher is inside hamburger menu panel.
  - On resize/orientation changes, switcher placement remains correct.

### G-007: Apple ID token cryptographic signature verification not yet implemented
- Severity: `P1`
- Status: `Open`
- Contract area: OAuth hardening
- Exact files:
  - `/Users/avrohom/Downloads/journeyatlas/atlas-concierge/crates/api/src/lib.rs`
- Implementation plan:
  1. Validate Apple `id_token` signature via Apple JWKS (kid/alg selection).
  2. Cache JWKS keys with TTL and rotation support.
  3. Reject unsigned/invalid signatures before claim parsing.
- Acceptance criteria:
  - Callback rejects tokens with invalid signature/key mismatch.
  - JWKS fetch and cache behavior is observable and tested.

### G-008: Stripe Apple Pay enablement requires dashboard/domain config proof
- Severity: `P1`
- Status: `Open` (code-ready, platform config pending)
- Contract area: Billing
- Exact files:
  - `/Users/avrohom/Downloads/journeyatlas/atlas-concierge/crates/api/src/lib.rs`
  - `/Users/avrohom/Downloads/journeyatlas/docs/operations/api-production-deploy.md`
- Implementation plan:
  1. Verify Stripe domain registration for `atlasmasa.com` and `www.atlasmasa.com`.
  2. Confirm Apple Pay wallet button appears in Stripe Checkout on Safari/iOS.
  3. Record runbook validation in ops doc.
- Acceptance criteria:
  - Stripe checkout on supported Safari device presents Apple Pay.
  - Billing webhook events continue to validate and process correctly.

### G-009: Repo governance hardening still needs org-level policy locks
- Severity: `P1`
- Status: `Open`
- Contract area: CI/repo security
- Exact files:
  - `/Users/avrohom/Downloads/journeyatlas/.github/workflows/ci.yml`
  - `/Users/avrohom/Downloads/journeyatlas/.github/workflows/security-scan.yml`
- Implementation plan:
  1. Enforce branch protection with required checks + signed commits.
  2. Restrict who can merge to protected branches.
  3. Enable mandatory secret scanning + push protection org-wide.
- Acceptance criteria:
  - Direct push/force push to protected branches is blocked.
  - Unsigned commits and failing checks cannot merge.

## P0 execution in this run
Closed in this execution:
- G-001, G-002, G-003, G-004, G-005, G-006

## Required validation commands (executed)
- `cargo fmt --all --check`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `cargo test -p atlas-tests --locked`
