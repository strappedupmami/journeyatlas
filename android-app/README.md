# Atlas Android

Native Android app for Atlas local-core Life OS.

## What it includes
- Local-first account/session model (Apple/Google/Passkey shell flows)
- Adaptive survey + memory graph
- Notes capture and memory ingestion
- Durable prompt queue with local reasoning output
- WorkManager-backed queue processing that resumes after reboot
- Execution stream (daily/mid/long horizon suggestions)
- Workspace sessions with cross-workspace shared memory
- In-app AI transparency (how Atlas is trained, how it works, why it exists)

## Stack
- Kotlin + Jetpack Compose
- Room (local DB)
- DataStore (session state)
- WorkManager (background queue durability)

## Performance and reliability hardening
- DB indexes on queue/memory/note/workspace hot paths.
- Encrypted-at-rest local persistence:
  - Android Keystore AES-GCM for session state and sensitive Room fields
  - no Android cloud backup (`allowBackup=false`) in production builds.
- TRUNCATE journal mode + bounded query thread pool for smoother I/O while limiting WAL residue.
- Queue safeguards:
  - max queue size cap
  - bounded per-run processing batch
  - timed worker budget
  - retention trimming for old completed jobs/memory.
- Boot + periodic watchdog scheduling to recover queue processing after restart/process death.
- Release build tuned with R8 + resource shrinking + profile installer.
- Compose list keying to reduce unnecessary recomposition churn.
- Device-aware queue mode:
  - balanced mode for weaker/older phones
  - high-performance burst mode for stronger devices (more queue throughput)

## Audience build flavors
- `yosef` flavor: package suffix `.yosef`
- `yasha` flavor: package suffix `.yasha`
- Both flavors are equivalent in functionality and exist for independent tester distribution.

## Build
1. Open `/Users/avrohom/Downloads/journeyatlas/android-app` in Android Studio.
2. Let Gradle sync and install SDK packages.
3. Run one of:
   - `app` / `yosefDebug` / `yashaDebug`
   - `yosefRelease` / `yashaRelease` for performance validation.

## Local LLM bridge (optional, local-first)
Prompt queue reasoning can use a local OpenAI-compatible endpoint first, then fall back to deterministic local reasoning.

BuildConfig keys:
- `LOCAL_LLM_ENABLED` (`true` by default)
- `LOCAL_LLM_ENDPOINT` (default: `http://127.0.0.1:8080/v1/chat/completions`)
- `LOCAL_LLM_MODEL` (default: `atlas-local-3b`)

Shared runtime launcher:

```bash
cd /Users/avrohom/Downloads/journeyatlas
ATLAS_LLM_HF_REPO=unsloth/Qwen2.5-3B-Instruct-GGUF:q4_k_m \
ATLAS_LLM_MODEL_ALIAS=atlas-local-3b \
./scripts/start-local-llm-runtime.sh
```

See `/Users/avrohom/Downloads/journeyatlas/LLM_ROLLOUT.md` for cross-platform rollout details.

## Notes
- This tier is designed for local compute/storage.
- Cloud capabilities can be layered later behind pro subscription.
- Practical expectation: older phones run smoothly for normal-heavy use; extreme concurrent workloads should still be paced via queue (by design) to protect device responsiveness and battery.
