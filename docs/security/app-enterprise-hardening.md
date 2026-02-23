# Atlas App Security Baseline (Enterprise Hardening)

This document tracks the app-level hardening posture for:
- iOS (`/ios-app`)
- macOS (`/macos-app`)
- Android (`/android-app`)
- Windows (`/windows-app`)

## 1) Implemented controls

### Shared principles
- Local-first storage and queue persistence (restart-safe).
- Sensitive output redaction in app system-output rails (Swift apps).
- HTTPS-only API access in production paths.
- Strictly bounded queue workers to avoid runaway device load and denial-of-service style degradation.

### iOS + macOS
- Encrypted persistence for session + prompt queue:
  - AES-GCM envelope encryption.
  - Key material stored in Keychain.
  - iOS uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
  - macOS uses Data Protection Keychain (`kSecUseDataProtectionKeychain`).
- Atomic write strategy with backup fallback and interrupted-queue recovery.
- HTTPS host allowlist enforcement through app environment and API request construction.

### Android
- Session state is encrypted with Android Keystore AES-GCM before DataStore write.
- Sensitive Room fields are encrypted before persistence:
  - notes (title/content)
  - queue payload fields (prompt/checkpoint/output/next action/errors)
  - memory value payloads
  - workspace session title/summary
- Strict API host/scheme enforcement in `ApiClient`:
  - HTTPS only
  - explicit allowlist for Atlas API domains
  - redirects disabled
- Manifest hardening:
  - `allowBackup=false`
  - cleartext traffic disabled
  - boot receiver non-exported
- Room journal mode set to `TRUNCATE` to reduce residual WAL data.

### Windows
- App state file now encrypted at rest using Windows DPAPI (`CurrentUser`) before disk write.
- Backward-compatible load path for legacy plaintext state (migration-safe).
- Existing atomic temp-file replace strategy retained.

## 2) Remaining external setup (required for full enterprise posture)

These are deployment responsibilities outside source code:

1. Enforce release signing and notarized distribution for each platform.
2. Turn on mandatory dependency scanning + signed artifact attestation in CI.
3. Add endpoint-level API abuse protections (WAF/rate limits) on hosted backend.
4. Configure production secrets in provider vaults only (never in app bundles).
5. Complete real auth provider wiring in production:
   - Apple Sign In
   - Google OAuth
   - passkey verification on backend
6. Add MDM policy profiles for enterprise-managed device fleets if required.

## 3) Verification checks before release

1. Run app auth flows on physical devices (network online/offline transitions).
2. Validate encrypted local persistence by inspecting local files for plaintext absence.
3. Validate queue recovery after forced app and device restarts.
4. Run security regression tests (auth boundary, malformed input, storage migration).
5. Verify `/health` + auth capability flags from production API host.

