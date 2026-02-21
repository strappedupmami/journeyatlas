# Repository Hardening Checklist (Atlas/אטלס)

This is the manual + code-backed hardening baseline for the Atlas/אטלס repo.

## 1) GitHub UI settings to enable now

In **Settings -> General**:
- Disable merge methods you do not use (recommend: keep only squash merge).
- Require linear history.
- Disable "Allow auto-merge" unless your approval policy requires it.

In **Settings -> Branches -> Add branch protection rule** for `main` (and `production` if used):
- Require a pull request before merging.
- Require approvals: `2`.
- Dismiss stale approvals when new commits are pushed.
- Require review from Code Owners.
- Require status checks to pass before merging:
  - `policy-guard`
  - `rust-ci`
  - `web-ci`
  - `dependency-audit`
  - `quarantine`
  - `sast-and-secrets`
- Require conversation resolution before merging.
- Require signed commits.
- Do not allow force pushes.
- Do not allow deletions.
- Restrict who can push/merge to authorized maintainers only.

In **Settings -> Code security and analysis**:
- Enable Dependabot alerts.
- Enable Dependabot security updates.
- Enable secret scanning.
- Enable push protection for secrets.
- Enable private vulnerability reporting.

In **Settings -> Actions -> General**:
- Allow only actions created by GitHub and verified creators, or use explicit allow-list.
- Enable "Require approval for all outside collaborators" for workflow runs.
- Keep `GITHUB_TOKEN` default permissions at `Read repository contents`.

## 2) Local developer protections

Install pre-commit and hooks:

```bash
pipx install pre-commit
cd /Users/avrohom/Downloads/journeyatlas
pre-commit install
pre-commit run --all-files
```

Hooks enforced by this repo:
- secret leak scan (`detect-secrets`)
- lockfile presence policy
- workflow action SHA pinning policy

## 3) Dependency supply-chain protections

Files:
- `.github/dependabot.yml`
- `.github/workflows/ci.yml`
- `.github/workflows/security-scan.yml`
- `.github/workflows/dependency-quarantine.yml`
- `.github/workflows/release-attestations.yml`
- `scripts/verify-lockfiles.sh`
- `scripts/verify-github-actions-pinning.sh`
- `scripts/verify-workflow-trust-boundaries.sh`
- `scripts/verify-dependency-pr-scope.sh`
- `scripts/dependency-quarantine-check.sh`
- `docs/security/post-solarwinds-model.md`

Key controls:
- automated Rust + npm dependency update PRs
- audit gates (`cargo audit`, `npm audit`)
- lockfile policy gates (`presence` + `sync-check`)
- SHA pin validation for all GitHub actions in workflows
- workflow trust-boundary policy (no `pull_request_target`, no `secrets: inherit`, no `write-all`)
- dependency-bot PR scope policy (bot PRs limited to dependency files only)
- suspicious dependency quarantine gate (labels + report + merge block on suspicious updates)
- signed release provenance and custom release attestations for tag builds

## 4) Account/session hardening in API

Current controls in Rust API:
- HttpOnly secure session cookies with domain scoping
- CSRF origin checks for cookie-authenticated write requests
- PKCE + state validation for Google OAuth
- Apple Sign In + passkey passwordless auth surface
- legacy `/v1/auth/social_login` route retired (returns 410)
- Passkey/WebAuthn sign-in support
- strict security headers middleware
- per-IP rate limiting, including dedicated auth start/finish abuse limits

## 5) Release provenance enforcement

Workflow:
- `.github/workflows/release-attestations.yml`

What it does:
- builds the release bundle from source at the tagged commit
- generates artifact provenance attestation (OIDC-signed)
- generates signed custom release attestation with run/ref/sha metadata

Operator policy:
- cut production releases from signed tags only (`v*`)
- verify release attestations before rollout in sensitive environments

## 6) Operational rules

- Never commit raw tokens, API keys, or OAuth secrets.
- Rotate credentials immediately after accidental disclosure.
- Treat every CI secret as compromised if fork policy or workflow permissions are changed.
- Keep auth surface strictly passwordless: Google OAuth, Apple Sign In, and passkeys only.
