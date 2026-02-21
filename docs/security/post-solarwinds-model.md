# Post-SolarWinds Security Model (Atlas/אטלס)

This document translates SolarWinds-style lessons into concrete controls for this repo and deployment stack.

## Threat model we assume

- A trusted dependency or build tool can become malicious.
- A CI workflow change can become a supply-chain pivot.
- A bot PR can be weaponized to alter runtime behavior outside dependency scope.
- A validly-authenticated user path can still be abused through weak trust boundaries.

## Controls implemented in-repo

### 1) Workflow trust boundaries

- All workflows are required to define explicit `permissions`.
- `pull_request_target` is disallowed.
- `secrets: inherit` is disallowed.
- `permissions: write-all` is disallowed.
- External actions must be SHA-pinned and owner allow-listed.

Enforced by:
- `/scripts/verify-workflow-trust-boundaries.sh`
- `/scripts/verify-github-actions-pinning.sh`
- `.github/workflows/ci.yml`
- `.github/workflows/security-scan.yml`

### 2) Dependency-chain integrity

- Lockfiles are mandatory.
- CI validates lockfiles are synchronized with manifests (`sync-check`).
- Dependency PR scope policy constrains bot PRs to dependency files only.
- Suspicious dependency updates are quarantined before merge.

Enforced by:
- `/scripts/verify-lockfiles.sh`
- `/scripts/verify-dependency-pr-scope.sh`
- `/scripts/dependency-quarantine-check.sh`
- `.github/workflows/ci.yml`
- `.github/workflows/dependency-quarantine.yml`

### 3) Artifact provenance + signed release attestations

- Tagged releases (`v*`) generate an immutable release bundle.
- GitHub artifact provenance attestation is generated via OIDC.
- A signed custom release attestation is generated over the same release subject.

Enforced by:
- `.github/workflows/release-attestations.yml`

### 4) Secret leakage prevention

- Local pre-commit scanning for private keys and high-entropy secrets.
- CI secret scanning + SAST on protected branches.

Enforced by:
- `/.pre-commit-config.yaml`
- `.github/workflows/security-scan.yml`

### 5) Runtime authentication hardening

- Strict passwordless auth surface (Google OAuth, Apple Sign In, Passkey).
- Legacy social login endpoint permanently disabled.
- Cookie-authenticated state-changing requests require allow-listed origin.
- Auth endpoints have dedicated abuse rate-limits.
- Secure session cookie attributes enforced.

Primary implementation:
- `/atlas-concierge/crates/api/src/lib.rs`

## Operational requirements (dashboard-level)

These are mandatory because they cannot be enforced from source code alone:

1. GitHub branch protection: 2 approvals, code owners, signed commits, no force-push/deletes.
2. GitHub Actions: outside-collaborator approval required.
3. GitHub Advanced Security toggles: secret scanning + push protection + Dependabot alerts/updates.
4. Token hygiene: rotate any key after accidental exposure; prefer short-lived credentials.
5. Require `quarantine` status check before merge on `main`.
6. Use signed tags (`v*`) for production release cutovers so attestations are generated.

## Incident response playbook (minimum)

When suspicious supply-chain behavior is detected:

1. Freeze deployments and disable auto-merge.
2. Revoke and rotate CI/deploy credentials.
3. Lock dependency update merges until triage is complete.
4. Diff recent workflow/script/dependency changes and identify first bad commit.
5. Inspect dependency quarantine report artifacts from failed PR checks.
6. Redeploy from known-good commit only after credential rotation.
