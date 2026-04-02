# LLM Rollout Source Of Truth (Cross-Chat Fast Read)

Last updated: 2026-02-26

## Mission
Ship real frontier-quality AI in Atlas apps for underserved users with low-friction access, local resilience, and no template-generated fake output.

## Non-Negotiables
- No non-AI templated/mock responses in user-facing generation paths.
- Every response must use current prompt + prior memory + survey/user context when available.
- Podcast mode is audio-first and must not silently degrade into text scripts.
- If internet is unavailable, queue waits and shows reconnect status (no cancel/fail loop by default).

## Production Routing Policy
### Text/chat reasoning (all apps)
- Primary provider/model: Gemini `gemini-3-flash-preview`.
- Fallback only on failure: OpenAI `gpt-5.2`.
- Fallback is failover, not dual synthesis, unless explicitly designed for a specific feature.

### Podcast pipeline (2-model)
- Stage A (script/planning): Gemini `gemini-3-flash-preview` (fallback `gpt-5.2`).
- Stage B (audio render): Gemini `gemini-2.5-pro-preview-tts`.
- Podcast output contract: audio artifact + metadata, no text-only fake podcast fallback.

## Official Gemini API Compliance (Must Follow)
### Gemini 3 guide rules
- Endpoint pattern: `POST /v1beta/models/{model}:generateContent`.
- Use `generationConfig.thinkingConfig.thinkingLevel` for Gemini 3 behavior control.
- Do not send `thinkingLevel` and legacy `thinkingBudget` together in one request (400 error).
- Gemini 3 is preview; pin model IDs explicitly and monitor release notes.

### Thought signature rule (Gemini 3/2.5 thinking models)
- When function calling returns `thoughtSignature`, pass it back exactly in subsequent turn history.
- Missing required signatures during Gemini 3 function-calling turns can produce 4xx validation errors.

### Gemini 2.5 Pro TTS rules
- Model: `gemini-2.5-pro-preview-tts`.
- Inputs: text only. Outputs: audio only.
- Set `generationConfig.responseModalities` to `["AUDIO"]`.
- Set `generationConfig.speechConfig.voiceConfig.prebuiltVoiceConfig.voiceName` (or multi-speaker config).
- Audio bytes come from `candidates[0].content.parts[0].inlineData.data` (base64).
- Multi-speaker supported up to 2 speakers.
- Capability limits: no function calling, no structured outputs, no thinking, no URL context for TTS model.

## Memory And Personalization Contract
- Both Stage A and Stage B prompts must include:
  - user prompt/request
  - survey signals
  - relevant memory and notes
  - workspace/concierge context
- Quiz, command, and execution outputs must inherit learned lessons and memory signals.

## UX Contract (iOS + Android)
- Concierge and Workspaces are chat-first, modern, minimal interfaces.
- Queueing is inside chat flow, not a separate standalone queue window.
- While generation is in-flight and user sends another prompt, offer exactly:
  - `Steer`
  - `Queue`
- Keep extra explanatory text out of core screens; move secondary detail behind compact controls/menus.

## Reliability Contract
- Queue processor is durable and restart-safe.
- On connectivity loss: show waiting/reconnect state and resume automatically when network returns.
- Provider/model errors must be explicit and actionable in logs and UI.

## Official References
- Gemini 3 Developer Guide: https://ai.google.dev/gemini-api/docs/gemini-3
- Gemini Thinking: https://ai.google.dev/gemini-api/docs/thinking
- Gemini Thought Signatures: https://ai.google.dev/gemini-api/docs/thought-signatures
- Gemini TTS Guide: https://ai.google.dev/gemini-api/docs/speech-generation
- Gemini 2.5 Pro TTS model page: https://ai.google.dev/gemini-api/docs/models/gemini-2.5-pro-preview-tts
- Gemini models catalog: https://ai.google.dev/gemini-api/docs/models

## New Chat Bootstrap
Use this starter line in new chats:

`Read /Users/avrohom/Downloads/BlackHaven/docs/engineering/GEMINI_DEVELOPER_GUIDE_IMPORT.md first, then /Users/avrohom/Downloads/BlackHaven/LLM_ROLLOUT.md and /Users/avrohom/Downloads/BlackHaven/CHAT_CONTINUITY.md, then continue implementation under those contracts.`
