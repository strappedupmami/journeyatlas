# BlackHaven End-User Readiness

This checklist is grounded in the current repo plus the PDF request to close the gap between concept and real-world usability.

## Already implemented in code/product

- BlackHaven website now sells the product as an execution-first command center instead of a generic local-AI shell
- Separate BlackHaven web positioning and downloads flow
- Native product surfaces for survey, memory, queueing, workspaces, remote control, and proactive execution
- Local-first and resilience-oriented product story
- Confidence-aware reasoning already present in app code paths
- Desktop-led product model with mobile companion surfaces already reflected in app capabilities

## Still needs owner-side completion

- Publish signed production installers for macOS and Windows
- Set real values for:
  - `NEXT_PUBLIC_BLACKHAVEN_MACOS_DOWNLOAD_URL`
  - `NEXT_PUBLIC_BLACKHAVEN_WINDOWS_DOWNLOAD_URL`
  - `NEXT_PUBLIC_BLACKHAVEN_SUPPORT_EMAIL`
  - `NEXT_PUBLIC_BLACKHAVEN_INSTALL_GUIDE_URL`
- Verify support inbox monitoring and response ownership
- Verify production auth and billing flows with clean accounts
- Publish and review privacy, terms, and any refund/subscription copy implied by the product
- Verify first-run value in the actual customer journey:
  - install
  - sign in
  - complete enough survey/setup to unlock execution stream value
  - receive a useful first proactive task or guided-learning output
- Run real-device testing for:
  - first install
  - local AI setup
  - remote pairing
  - LAN access
  - degraded internet behavior
  - backup-power continuity behavior
- Publish minimum hardware expectations for:
  - local AI disk space
  - RAM/performance tier
  - desktop home-base uptime and power assumptions

## Minimum launch bar

Do not treat the product as broadly customer-ready until a new user can:

1. Find the correct installer.
2. Install without OS trust warnings blocking them.
3. Sign in and unlock paid features.
4. Complete onboarding without founder intervention.
5. Understand what is verified, estimated, local-only, or cloud-dependent.
6. Reach support and follow a documented recovery path if setup fails.
7. Understand that the desktop app is the main command center and mobile acts as the companion/control layer.
8. Experience the execution-stream promise in the first session instead of seeing only setup friction.
