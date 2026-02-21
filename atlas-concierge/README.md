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
