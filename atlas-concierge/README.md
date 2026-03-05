# Atlas Concierge (Rust)

Concierge-grade AI problem solver backend for the Atlas/אטלס ecosystem.

## Core design
- Rules-first deterministic planner
- Hybrid retrieval (keyword + optional vector)
- Burn-augmented ML (optional feature flag)
- Policy gates for safety/compliance
- CLI + HTTP API interfaces
- Hebrew research corpus + trainable intent dataset (`kb/research`, `kb/training`)

## Workspace crates
- `atlas-core`: domain models, policies, intent rules, response templates
- `atlas-retrieval`: KB ingestion, chunking, hybrid search, embedding trait
- `atlas-ml`: fallback embeddings + Burn feature (`burn-ml`)
- `atlas-agents`: orchestration pipeline/state machine
- `atlas-storage`: memory + SQLite persistence
- `atlas-observability`: tracing + metrics snapshot
- `atlas-api`: Axum endpoints and middleware
- `atlas-cli`: operator-friendly local commands
- `atlas-tests`: integration tests

See run instructions in `docs/RUNBOOK.md`.

## Cloud AI Providers
Backend premium inference supports both:
- OpenAI (`ATLAS_OPENAI_API_KEY`, `ATLAS_OPENAI_MODEL`, `ATLAS_OPENAI_REASONING_EFFORT`)
- Google DeepMind Gemini (`ATLAS_GEMINI_API_KEY`, `ATLAS_GEMINI_MODEL`, `ATLAS_GEMINI_TEMPERATURE`, `ATLAS_GEMINI_MAX_OUTPUT_TOKENS`, optional `ATLAS_GEMINI_THINKING_LEVEL=low|medium|high`)

Provider preference/fallback can be set with:
- `ATLAS_AI_PROVIDER_PREFERENCE=auto|openai|gemini`

Security note:
- Keep provider keys on the backend only. Mobile/web apps should call this API and must not ship Gemini/OpenAI keys in client binaries or frontend source.
