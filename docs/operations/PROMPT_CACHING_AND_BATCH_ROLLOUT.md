# Prompt Caching And Batch Rollout

This closes part of the gap from the PDF about token efficiency for giant-memory agent workflows.

## Implemented in code now

- OpenAI premium chat payloads now put stable context before the dynamic task payload.
- Stable context gets a deterministic cache key so prompt-prefix behavior is observable and debuggable.
- Gemini premium chat payloads now support an optional pre-created cached-content attachment with `ATLAS_GEMINI_CONTEXT_CACHE_NAME`.
- New backend endpoint: `POST /v1/memory/batch/export`
  - authenticated
  - respects `memory_opt_in`
  - returns JSONL for non-urgent memory compaction work
  - supports `provider=openai` and `provider=generic_jsonl`

## What still needs operator work

- OpenAI:
  - Set `ATLAS_OPENAI_API_KEY`
  - Use a stable system prompt and keep dynamic request data at the end of the payload
  - If you want large-scale batch savings, upload the returned JSONL from `/v1/memory/batch/export` to the provider batch pipeline and run a worker that ingests results back into memory/lifelog storage

- Gemini:
  - Set `ATLAS_GEMINI_API_KEY`
  - If using Google cached content, create the cache object first and set `ATLAS_GEMINI_CONTEXT_CACHE_NAME`
  - Refresh that cache whenever the stable long-term context changes materially

## Real-world readiness note

The new code improves prompt structure and gives you a real export path for deferred work, but full production savings still require:

1. A provider-side batch upload/execution worker.
2. A results ingester that writes compaction outputs back into durable memory storage.
3. Monitoring for cache hit behavior, batch failures, and stale cached-content rotation.
4. A production vector-capable store if you want true large-memory semantic retrieval instead of the current lightweight relevance scoring path.
