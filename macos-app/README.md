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

## Local LLM bridge (optional, local-first)
Queue/feed/workspace inference can use a local OpenAI-compatible endpoint first, then fall back to deterministic local logic.

Runtime keys (`UserDefaults`):
- `atlas.local.llm.enabled` (`true` by default)
- `atlas.local.llm.endpoint` (default: `http://127.0.0.1:8080/v1/chat/completions`)
- `atlas.local.llm.model` (default: `atlas-local-3b`)

Shared runtime launcher:

```bash
cd /Users/avrohom/Downloads/journeyatlas
ATLAS_LLM_HF_REPO=unsloth/Qwen2.5-3B-Instruct-GGUF:q4_k_m \
ATLAS_LLM_MODEL_ALIAS=atlas-local-3b \
./scripts/start-local-llm-runtime.sh
```

See `/Users/avrohom/Downloads/journeyatlas/LLM_ROLLOUT.md` for cross-platform rollout details.

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
