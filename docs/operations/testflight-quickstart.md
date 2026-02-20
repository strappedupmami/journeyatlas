# Atlas Masa TestFlight Quickstart (iOS + macOS)

Use this checklist to get first internal builds into TestFlight quickly.

## 1) Apple Developer: create App IDs

From **Certificates, Identifiers & Profiles -> Identifiers -> +**:

1. Create iOS App ID
   - Description: `Atlas Masa iOS`
   - Bundle ID (Explicit): `com.atlasmasa.ios`
   - Enable capabilities:
     - `Sign in with Apple`
     - `In-App Purchase` (for later subscription work)
2. Create macOS App ID
   - Description: `Atlas Masa macOS`
   - Bundle ID (Explicit): `com.atlasmasa.macos`
   - Enable capabilities:
     - `Sign in with Apple`
     - `In-App Purchase` (for later subscription work)

## 2) Apple Developer: create Services ID (website Sign in with Apple)

From **Identifiers -> + -> Services IDs**:

- Description: `Atlas Masa Web`
- Identifier: `com.atlasmasa.web`
- Enable `Sign in with Apple`
- Configure web domain/return URL later when `api.atlasmasa.com` is live.

## 3) Apple Developer: create Sign in with Apple key

From **Keys -> +**:

- Key Name: `AtlasMasaSignIn`
- Enable `Sign in with Apple`
- Click `Configure` and choose primary App ID (`com.atlasmasa.ios` or `com.atlasmasa.macos`)
- Download `.p8` once and save securely.

## 4) App Store Connect: create app records

From **App Store Connect -> My Apps -> + New App**:

1. Create iOS app record
   - Name: `Atlas Masa`
   - Primary Language: choose your default
   - Bundle ID: `com.atlasmasa.ios`
   - SKU: `atlasmasa-ios-001`
2. Create macOS app record
   - Name: `Atlas Masa Desktop`
   - Bundle ID: `com.atlasmasa.macos`
   - SKU: `atlasmasa-macos-001`

## 5) Generate Xcode projects

```bash
cd /Users/avrohom/Downloads/journeyatlas/ios-app
xcodegen generate

cd /Users/avrohom/Downloads/journeyatlas/macos-app
xcodegen generate
```

## 6) Xcode signing setup

In each generated project:

- Target -> Signing & Capabilities
  - Team: `BW93SGS88H`
  - Bundle ID must match App ID
  - Add capability: `Sign in with Apple`
  - Add capability: `In-App Purchase` (optional now, useful later)

## 7) Upload internal TestFlight builds

For iOS app:

1. Product -> Archive (Any iOS Device)
2. Organizer -> Distribute App -> App Store Connect -> Upload

For macOS app:

1. Product -> Archive (Any Mac)
2. Organizer -> Distribute App -> App Store Connect -> Upload

Then in App Store Connect -> TestFlight, wait for processing and add internal testers.

## Notes

- Website Stripe + Apple Pay is separate from in-app purchases.
- iOS/macOS digital subscriptions should use StoreKit for App Review compliance.
