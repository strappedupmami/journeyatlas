# Atlas Quality Standard (Million-Dollar Bar)

## Why this exists
Atlas ships across iOS, macOS, Android, Windows, and web. Quality must be intentional, repeatable, and enforced in CI, not dependent on taste in a single PR.

## Product quality requirements
- No placeholder, meme, or low-signal product copy in production surfaces.
- Chat surfaces must feel intentional and focused (clear hierarchy, minimal clutter, consistent tone).
- UI changes require both visual consistency and technical reliability checks.
- Backend changes must preserve strict API contracts, observability, and failure safety.

## Engineering quality requirements
- Warnings are treated as release blockers where supported.
- Every platform must have an automated quality gate path.
- Critical checks must run in CI before merge.
- New features should be modular and reviewable (clear boundaries, no hidden side effects).

## Required gate before ship
Run from repo root:

```bash
./scripts/quality-gate.sh
```

For strict mode (fail if any platform check is skipped):

```bash
ATLAS_QUALITY_STRICT=1 ./scripts/quality-gate.sh
```

If you are in a network-restricted/offline environment and cannot regenerate lockfiles:

```bash
ATLAS_QUALITY_LOCKFILE_MODE=presence ./scripts/quality-gate.sh
```

## Included checks
- Policy guards (workflow security, lockfiles, dependency PR scope)
- Product copy quality guard (`scripts/verify-product-copy-quality.sh`)
- Web lint + typecheck + production build
- Rust fmt + clippy + tests
- Swift syntax parse sweep (iOS + macOS sources)
- Android and Windows checks when toolchains/wrappers are available

## Release rule
If the gate is red, release is red.
