# Gemini Developer Guide Import (Official-Flow Digest)

Last updated: 2026-02-26
Scope: practical import of official Gemini developer guidance for Atlas implementation.

## Official Sources
- Gemini 3 Developer Guide: https://ai.google.dev/gemini-api/docs/gemini-3
- Gemini Thinking Guide: https://ai.google.dev/gemini-api/docs/thinking
- Gemini Thought Signatures: https://ai.google.dev/gemini-api/docs/thought-signatures
- Gemini Speech Generation (TTS): https://ai.google.dev/gemini-api/docs/speech-generation
- Gemini 2.5 Pro TTS model page: https://ai.google.dev/gemini-api/docs/models/gemini-2.5-pro-preview-tts
- Gemini model catalog: https://ai.google.dev/gemini-api/docs/models

## What This File Is
- This is a compact engineering import for fast reuse in new chats and implementation passes.
- It captures official request/response patterns and constraints we must follow.
- It is intentionally implementation-focused, not a full mirror of external docs.

## A) Gemini 3 (Primary Reasoning Model)

### Model policy for Atlas
- Primary model: `gemini-3-flash-preview`.
- Use this for planning, reasoning, response drafting, quiz creation, and podcast script planning.
- Keep `gpt-5.2` as fallback only when Gemini request fails.

### REST request shape (official pattern)
```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent" \
  -H "Content-Type: application/json" \
  -H "x-goog-api-key: ${GEMINI_API_KEY}" \
  -d '{
    "contents": [{
      "role": "user",
      "parts": [{ "text": "Your prompt here" }]
    }],
    "generationConfig": {
      "thinkingConfig": {
        "thinkingLevel": "medium"
      }
    }
  }'
```

### Thinking config rules (critical)
- Use `generationConfig.thinkingConfig.thinkingLevel` for Gemini 3.
- Do not send `thinkingLevel` and legacy `thinkingBudget` together in one request.
- For `gemini-3-flash-preview`, avoid legacy `thinkingBudget` compatibility behavior.

### Output extraction (text)
- Read from `candidates[].content.parts[].text`.
- Treat empty text as a provider failure and trigger fallback path.

## B) Thought Signatures (When Using Tool Calling)

### Required handling
- If Gemini returns `thoughtSignature` in assistant content parts, keep those parts unchanged.
- Send those exact assistant parts back in the next request history when continuing the turn chain.
- Do not drop, merge, or mutate signed thought parts.

### Why this matters
- Missing/altered thought-signature parts can cause Gemini request validation failures in follow-up turns.

## C) Gemini 2.5 Pro TTS (Podcast Audio Render Stage)

### Model policy for Atlas
- TTS model: `gemini-2.5-pro-preview-tts`.
- Use this for final podcast audio generation only (stage B of pipeline).

### Capability constraints from official docs
- Input modality: text only.
- Output modality: audio only.
- Does not support function calling.
- Does not support structured outputs.
- Does not support thinking.
- Multi-speaker generation supports up to 2 speakers.
- Model page limits (as of 2026-02-25):
  - max input tokens: 1,500
  - max output tokens: 16,000
- Typical output MIME contracts observed in official examples:
  - `audio/L16;rate=24000` (raw PCM)
  - `audio/wav` (wrapped PCM)

### REST request shape (single-speaker audio)
```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro-preview-tts:generateContent" \
  -H "Content-Type: application/json" \
  -H "x-goog-api-key: ${GEMINI_API_KEY}" \
  -d '{
    "contents": [{
      "role": "user",
      "parts": [{ "text": "Read this as a concise tactical podcast intro..." }]
    }],
    "generationConfig": {
      "responseModalities": ["AUDIO"],
      "speechConfig": {
        "voiceConfig": {
          "prebuiltVoiceConfig": {
            "voiceName": "Kore"
          }
        }
      }
    }
  }'
```

### Audio extraction contract
- Audio payload is returned in `candidates[0].content.parts[0].inlineData.data` (base64).
- `inlineData.mimeType` indicates the audio format.
- Decode base64 -> bytes -> save as file (for playback/download/share).

## D) Atlas 2-Model Podcast Pipeline (Production Contract)

### Stage 1: podcast planning/script
- Provider order: Gemini 3 Flash first, GPT-5.2 fallback.
- Input context must include:
  - prompt
  - conversation memory
  - user survey/profile signals
  - workspace/concierge scope
- Output: structured podcast plan (segments, speaker style, timing, key takeaways).

### Stage 2: audio generation
- Provider: Gemini 2.5 Pro TTS.
- Input: stage-1 final script text only.
- Output: audio artifact + metadata (`mimeType`, duration estimate, voice config used).
- No text fallback output in podcast mode.

## E) UI/UX Integration Requirements (iOS + Android)
- Podcast output type is audio-first in chat flow.
- While audio is processing, show generation status with retry-safe queue state.
- If offline, show waiting-to-reconnect and keep job queued.
- If TTS unavailable, show explicit provider error and keep job resumable.
- Queueing controls are inside chat composer flow (not separate queue windows).

## F) Error Handling + Fallback Rules
- Gemini 3 Flash stage fails -> retry policy -> GPT-5.2 fallback.
- Gemini TTS stage fails -> retry policy -> mark audio generation failed with explicit reason (no fake text podcast output).
- Always log:
  - provider
  - model
  - latency
  - failure code/message
  - fallback invocation flag

## G) Implementation Checklist
- Backend:
  - add podcast generation endpoint that runs stage 1 then stage 2
  - persist audio metadata and artifact reference
  - include user memory/survey context in stage 1 prompt builder
- iOS:
  - podcast chat card renders audio player, not text script bubble
  - queue states: queued/running/waiting reconnect/done/failed
- Android:
  - match iOS output type UX, queue behavior, and podcast player surface
  - keep model routing contract identical to iOS/backend

## New Chat Bootstrap
Use this line:

`Read /Users/avrohom/Downloads/BlackHaven/docs/engineering/GEMINI_DEVELOPER_GUIDE_IMPORT.md first, then continue implementation exactly under these contracts.`

## New Chat Intake Checklist (Mandatory)
- Confirm podcast is implemented as 2-model pipeline, not single-call text generation.
- Confirm stage ordering:
  - stage 1 reasoning/script (`gemini-3-flash-preview`, fallback `gpt-5.2`)
  - stage 2 TTS audio render (`gemini-2.5-pro-preview-tts`)
- Confirm stage 1 context includes user prompt + survey signals + memory/history.
- Confirm podcast output is audio artifact metadata and player-ready bytes, not script text bubble.
- Confirm retry/fallback behavior:
  - Gemini stage 1 failure -> GPT fallback
  - TTS stage failure -> explicit failed state (no fake text substitution)
- Confirm iOS and Android UI parity for:
  - output-type selector with podcast mode
  - in-flight handling and queue/reconnect state
  - audio playback surface once podcast completes
