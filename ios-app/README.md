# Atlas Masa iOS App

Native Swift Life OS app for movement-based living/work execution.

## Product role
- **App is the actual Life OS** (local reasoning, queue, memory, orchestration).
- **Website is the sales layer** (signup, pricing, van rental intake, tier upgrade).

## Included now
- Premium red-night visual system + modern serif/sans hierarchy
- Command Center (daily / mid-term / long-horizon planning)
- Adaptive deep survey (branching, long-form onboarding)
- Prompt queue + local reasoning worker
- Notes + long-term memory insights + local memory wipe control
- Execution loop (proactive outputs with local-first fallback)
- Mobility/van rental intent capture for planning alignment
- Auth access shell: Apple, Google placeholder, passwordless local flow
- Tiering model in-app:
  - Tier 1 local reasoning (trial)
  - Tier 2 cloud reasoning mode switch

## Project generation
```bash
brew install xcodegen
cd /Users/avrohom/Downloads/journeyatlas/ios-app
xcodegen generate
```

Then open `/Users/avrohom/Downloads/journeyatlas/ios-app/AtlasMasaIOS.xcodeproj` in Xcode.

## Build note
`xcodebuild` requires full Xcode.app (not only Command Line Tools).

## API target
Default API base: `https://api.atlasmasa.com`

Override at runtime via `UserDefaults` key:
- `atlas.api.base`
