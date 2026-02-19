## Summary

- What changed?
- Why now?

## Security Checklist

- [ ] No secrets/tokens added in code, logs, docs, or screenshots
- [ ] OAuth/session changes include cookie and CSRF review
- [ ] Any new dependency is justified and pinned/locked
- [ ] Rust API inputs are validated and length-limited
- [ ] Privileged endpoints enforce auth and least privilege

## Verification

- [ ] `./scripts/verify-lockfiles.sh presence`
- [ ] `./scripts/verify-github-actions-pinning.sh`
- [ ] Relevant tests passed
