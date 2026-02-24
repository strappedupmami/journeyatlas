# Atlas Windows (Local-First)

Production-target Windows app for Atlas local compute + local storage workflows.

## What is implemented
- Full workspace surfaces (specialized layouts, not one generic screen):
  - `Command Center`
  - `Adaptive Survey`
  - `Prompt Queue`
  - `Execution Stream`
  - `Memory + Notes`
  - `Workspaces`
  - `Access`
  - `AI Guide`
  - `Mobility + Ops`
  - `System Output`
- Persistent local state under `%LOCALAPPDATA%/Atlas/Windows/atlas_windows_state_v1.json`
  - encrypted at rest with Windows DPAPI (`CurrentUser` scope)
- Resumable queue (queued/running prompts recover after restart)
- Local reasoning engine with emergency/wealth/execution routing
- Dynamic performance profile:
  - detects cores + memory
  - tunes queue workers (more concurrency on stronger PCs)

## Build prerequisites
- Windows 11
- Visual Studio 2022 (17.8+) with:
  - `.NET desktop development`
  - `Windows application development` (WinUI 3)
- .NET 8 SDK

## Run
1. Open `/Users/avrohom/Downloads/journeyatlas/windows-app/AtlasMasaWindows/AtlasMasaWindows.csproj` in Visual Studio.
2. Select `x64` for most modern PCs, or `ARM64` for ARM laptops.
3. Press `F5`.

## Local LLM bridge (optional, local-first)
Prompt queue reasoning can use a local OpenAI-compatible endpoint first, then fall back to deterministic local reasoning.

Environment variables:
- `ATLAS_LOCAL_LLM_ENABLED` (`true` by default)
- `ATLAS_LOCAL_LLM_ENDPOINT` (default: `http://127.0.0.1:8080/v1/chat/completions`)
- `ATLAS_LOCAL_LLM_MODEL` (default: `atlas-local-3b`)

Shared runtime launcher:

```bash
cd /Users/avrohom/Downloads/journeyatlas
ATLAS_LLM_HF_REPO=unsloth/Qwen2.5-3B-Instruct-GGUF:q4_k_m \
ATLAS_LLM_MODEL_ALIAS=atlas-local-3b \
./scripts/start-local-llm-runtime.sh
```

See `/Users/avrohom/Downloads/journeyatlas/LLM_ROLLOUT.md` for cross-platform rollout details.

## Distribution tracks requested
- `Yosef + Benny` Windows track:
  - publish `x64` `Release`
  - produce MSIX installer in `Publish`.
- `Yosef + Yasha` Android track:
  - use Android flavor builds (`yosefRelease`, `yashaRelease`) in `/Users/avrohom/Downloads/journeyatlas/android-app`.

## Performance intent for strong PCs
- Queue concurrency increases automatically on high-core systems.
- ReadyToRun publish is enabled in project settings.
- Server GC + tiered JIT enabled for sustained heavy local use.
