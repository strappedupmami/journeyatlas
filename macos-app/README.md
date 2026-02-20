# Atlas Masa macOS App

SwiftUI scaffold for Atlas Masa desktop client.

## Included now
- Auth shell with native `Sign in with Apple` capture
- Apple web OAuth launcher (for current backend web flow)
- Adaptive deep survey screen
- Notes/memory capture screen
- Proactive feed screen
- Subscription placeholder with StoreKit roadmap
- System output log view

## Project generation
This repo includes an XcodeGen spec:
- `macos-app/project.yml`

Generate project:
```bash
brew install xcodegen
cd /Users/avrohom/Downloads/journeyatlas/macos-app
xcodegen generate
```

Then open `AtlasMasaMacOS.xcodeproj` in Xcode.

## API target
Default API base: `https://api.atlasmasa.com`

Override at runtime via `UserDefaults` key:
- `atlas.api.base`
