# Quick Context: Local-First AI for Everyone

## Plain-Language Meaning of the Direction
The goal is to ship a real, high-quality AI assistant in all Atlas apps without forcing users into expensive subscriptions or strict usage limits.

We will:
- Use a strong pretrained local LLM now so users get real AI quality immediately.
- Customize that local stack for Atlas use cases (memory, workflow, mobility, execution, etc.).
- Build an original Atlas model gradually in parallel, using lessons from real usage and realistic training limits.

## Why This Matters
- Most people are priced out of premium "unlimited AI" plans.
- Local inference can reduce recurring cost and remove artificial usage caps.
- Atlas should deliver frontier-like capability to underserved users first, not last.

## Product Requirements (Non-Negotiable)
- Unique prompts must produce unique, high-quality responses.
- Responses must use:
  - the current prompt,
  - prior memory,
  - and relevant conversation history.
- Experience should feel like a real assistant (ChatGPT-level or better for Atlas domains).
- Local-first by default; cloud should be optional for extra depth, not required for baseline quality.

## Implementation Strategy
### Phase 1 (Now)
- Integrate pretrained on-device/local-runtime LLM in:
  - iOS
  - macOS
  - Android
  - Windows
- Keep deterministic local reasoners as reliability fallback.
- Route as: `LLM first -> fallback second`.
- Add a shared context builder that injects notes, memory, check-ins, and workspace state.

### Phase 2 (Parallel, Slower)
- Develop original Atlas model gradually.
- Use real product feedback to decide where fine-tuning is worth the cost.
- Respect compute/data/time limits and prioritize practical gains.

## Engineering Rules for Future Sessions
- Prioritize end-to-end shipping over abstract planning.
- Keep local mode fast and stable on weaker devices.
- Add graceful degradation when model/runtime is unavailable.
- Track quality, latency, fallback rate, and crash-free behavior.

## Re-Use Prompt for New Chats
Use this at the start of a new chat:

"Read `/Users/avrohom/Downloads/journeyatlas/QUICK_CONTEXT.md` and continue from that context."

