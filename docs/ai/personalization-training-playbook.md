# Atlas/אטלס AI Personalization Training Playbook

This document defines a production-safe path for long-term, precise personalization without training directly on raw private conversation archives.

## 1) Training strategy

Atlas/אטלס uses a layered memory strategy:
- **Structured profile memory**: style, risk, language, preferences.
- **Adaptive survey memory**: dynamic answers for daily/mid/long-horizon planning.
- **Execution memory**: user notes and imported memory events.
- **Model runtime**: GPT-5.2 API calls with high reasoning effort, enriched by the above memory.

The base model is not fine-tuned with raw private chats by default. Instead, we use retrieval-augmented personalization to keep user control, auditability, and deletion support.

## 2) What can be imported now

The Rust API exposes:
- `POST /v1/memory/import`

Authenticated users can import notebook/chat-derived memory items in batches:

```json
{
  "items": [
    {
      "title": "North route pattern",
      "content": "User performs best with early departures and two deep-work blocks before noon.",
      "tags": ["route", "productivity", "north"],
      "source": "notebooklm",
      "happened_at": "2026-02-19T08:30:00Z"
    }
  ]
}
```

These entries are sanitized, persisted, and fed back into proactive execution output and premium chat context.

## 3) Data contracts for long-term memory

For each memory item, enforce:
- factual content (no speculative diagnostics),
- clear time horizon labels (`daily`, `mid_term`, `long_term`),
- source metadata (`notebooklm`, `support_call`, `user_note`, etc.),
- safe tags (alphanumeric, `_`, `-`).

Recommended tag taxonomy:
- `goal_revenue`
- `goal_health`
- `goal_charity`
- `constraint_time`
- `constraint_budget`
- `travel_pattern_heavy_commute`
- `energy_morning_peak`

## 4) Guardrails

- Never store credentials/tokens in memory notes.
- Never ingest private third-party data without user consent.
- Keep user-level deletion capability for all memory records.
- Keep OAuth/session controls separate from AI memory store.

## 5) Next production upgrades

- Add vector search index for semantic memory retrieval.
- Add TTL + archival policies by memory type.
- Add user-facing memory audit timeline (what was learned, when, and why).
- Add explicit consent toggles for each memory source class.

## 6) Local app model loop

For iOS/macOS on-device model updates, use:
- `/Users/avrohom/Downloads/journeyatlas/docs/ai/local-model-training.md`

This loop trains and regenerates local Swift model payloads without cloud inference.
