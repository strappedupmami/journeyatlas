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
- World Monitor tab (embedded dashboard with hosted/local endpoint switch)
- Auth access shell: Apple + Google OAuth web start, passwordless local flow
- Tiering model in-app:
  - Tier 1 local reasoning
  - Tier 2 cloud reasoning mode switch

## Project generation
```bash
brew install xcodegen
cd /Users/avrohom/Downloads/BlackHaven/macos-app
xcodegen generate
```

Then open `/Users/avrohom/Downloads/BlackHaven/macos-app/AtlasMasaMacOS.xcodeproj` in Xcode.

## Build note
`xcodebuild` requires full Xcode.app (not only Command Line Tools).

## API target
Default API base: `https://api.atlasmasa.com`

Queue reasoning now uses shared backend `/v1/chat` first, then falls back to local inference if backend/session is unavailable.

Override at runtime via `UserDefaults` key:
- `atlas.api.base`

## Local LLM bridge (optional, local-first)
Queue/feed/workspace inference can use a local OpenAI-compatible endpoint first, then fall back to deterministic local logic.

Runtime keys (`UserDefaults`):
- `atlas.local.llm.enabled` (`true` by default)
- `atlas.local.llm.endpoint` (default: `http://127.0.0.1:11434/v1/chat/completions`)
- `atlas.local.llm.model` (default: `auto`; set fixed model to override policy)
- `atlas.local.llm.model_catalog` (optional ordered list, comma-separated; heavy to light)

Environment keys:
- `ATLAS_RUST_REASONER_BIN` (optional absolute path to `atlas-rust-reasoner`)

Default auto model catalog (heavy to light):
- `llama3.1:70b`
- `qwen2.5:32b`
- `deepseek-r1:14b`
- `qwen2.5:7b`
- `llama3.2:latest`

Rust policy mode (macOS + Windows):
- picks model from catalog based on hardware
- adjusts reasoning budget (passes/tokens/context/timeout)
- still supports fixed model override when needed

Shared runtime launcher:

```bash
cd /Users/avrohom/Downloads/BlackHaven
ATLAS_LLM_HF_REPO=unsloth/Qwen2.5-3B-Instruct-GGUF:q4_k_m \
ATLAS_LLM_MODEL_ALIAS=atlas-local-3b \
./scripts/start-local-llm-runtime.sh
```

See `/Users/avrohom/Downloads/BlackHaven/LLM_ROLLOUT.md` for cross-platform rollout details.

## World Monitor integration
macOS now includes a dedicated `World` tab that embeds World Monitor via `WKWebView`.

- Hosted preset: `https://worldmonitor.app`
- Local preset: `http://127.0.0.1:5173`
- Custom endpoint: editable URL field inside the tab

To run from the added local folder:

```bash
cd /Users/avrohom/Downloads/BlackHaven/worldmonitor-main
npm install
npm run dev
```

Then click `Use Local Dev` in the macOS app `World` tab.

## Local model training
Train/update the on-device travel-design local model from project data:

```bash
cd /Users/avrohom/Downloads/BlackHaven
./scripts/train-local-model-loop.sh
```

Continuous retraining loop:

```bash
cd /Users/avrohom/Downloads/BlackHaven
RUN_FOREVER=1 INTERVAL_SECONDS=1800 ./scripts/train-local-model-loop.sh
```
