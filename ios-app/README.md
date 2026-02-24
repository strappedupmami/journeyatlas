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
  - Tier 1 local reasoning
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

## Local LLM bridge (optional, local-first)
Queue reasoning can use:
- an OpenAI-compatible local/hosted endpoint, or
- Gemini cloud inference using a Gemini API key,
then fallback to deterministic local reasoning when unavailable.

Runtime keys (UserDefaults):
- `atlas.local.llm.provider` (`openai_compatible` by default, or `gemini`)
- `atlas.local.llm.endpoint` (default: `http://127.0.0.1:8080/v1/chat/completions`)
- `atlas.local.llm.model` (default depends on provider: `atlas-local-3b` for OpenAI-compatible, `gemini-2.0-flash` for Gemini)

Runtime secret (Keychain, not UserDefaults):
- service: `com.atlasmasa.local.llm`
- account: `provider_api_key`
- value: provider API key (Gemini key for `gemini`, optional bearer token for OpenAI-compatible endpoints)

In-app configuration:
- Open `More` → `Account` → `Model runtime`
- Select provider, set model/endpoint, and save API key securely.

Notes:
- Plain `http` is accepted only for `localhost` / `127.0.0.1`.
- On iOS simulator, `127.0.0.1` points to the Mac host runtime.
- Physical iOS devices typically need an HTTPS endpoint reachable over LAN/VPN.

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
