# LLM Rollout (Local-First Across All Apps)

## Goal
Ship high-quality AI output now with a pretrained local LLM, while building an original Atlas model in parallel over time.

## Runtime Contract
All apps are wired to call an OpenAI-compatible local endpoint first, then fall back to deterministic local reasoning.

- Endpoint expected: `http://127.0.0.1:8080/v1/chat/completions`
- Default model alias: `atlas-local-3b`
- Security rule: plain `http` is accepted only for `localhost` or `127.0.0.1` (otherwise use `https`).

## Start Local Runtime
Use the shared launcher:

```bash
cd /Users/avrohom/Downloads/journeyatlas
ATLAS_LLM_HF_REPO=unsloth/Qwen2.5-3B-Instruct-GGUF:q4_k_m \
ATLAS_LLM_MODEL_ALIAS=atlas-local-3b \
./scripts/start-local-llm-runtime.sh
```

Or point to a local GGUF file:

```bash
ATLAS_LLM_MODEL_PATH=/absolute/path/to/model.gguf \
ATLAS_LLM_MODEL_ALIAS=atlas-local-3b \
./scripts/start-local-llm-runtime.sh
```

## Platform Config
### iOS + macOS
`UserDefaults` keys:
- `atlas.local.llm.enabled` (`true` default)
- `atlas.local.llm.endpoint` (`http://127.0.0.1:8080/v1/chat/completions` default)
- `atlas.local.llm.model` (`atlas-local-3b` default)

### Android
`BuildConfig` fields in `app/build.gradle.kts`:
- `LOCAL_LLM_ENABLED`
- `LOCAL_LLM_ENDPOINT`
- `LOCAL_LLM_MODEL`

### Windows
Environment variables:
- `ATLAS_LOCAL_LLM_ENABLED` (`true` default)
- `ATLAS_LOCAL_LLM_ENDPOINT` (`http://127.0.0.1:8080/v1/chat/completions` default)
- `ATLAS_LOCAL_LLM_MODEL` (`atlas-local-3b` default)

## Prompt Behavior Requirement
Local LLM prompt building must always include:
- user prompt
- short memory snapshot (notes/history/session context)
- explicit JSON output schema

This keeps output unique, grounded, and actionable while preserving deterministic fallback safety.
