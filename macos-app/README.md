# Atlas/אטלס macOS App

Native Swift Life OS desktop app for deep planning and execution.

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
  - Tier 1 local reasoning
  - Tier 2 cloud reasoning mode switch

## Project generation
```bash
brew install xcodegen
cd /Users/avrohom/Downloads/journeyatlas/macos-app
xcodegen generate
```

Then open `/Users/avrohom/Downloads/journeyatlas/macos-app/AtlasMasaMacOS.xcodeproj` in Xcode.

## Build note
`xcodebuild` requires full Xcode.app (not only Command Line Tools).

## API target
Default API base: `https://api.atlasmasa.com`

Override at runtime via `UserDefaults` key:
- `atlas.api.base`

## Local model training
Train/update the on-device travel-design local model from project data:

```bash
cd /Users/avrohom/Downloads/journeyatlas
./scripts/train-local-model-loop.sh
```

Continuous retraining loop:

```bash
cd /Users/avrohom/Downloads/journeyatlas
RUN_FOREVER=1 INTERVAL_SECONDS=1800 ./scripts/train-local-model-loop.sh
```
