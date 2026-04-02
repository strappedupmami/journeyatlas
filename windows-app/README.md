# Atlas Windows (Local-First)

Production-target Windows app for Atlas local compute + local storage workflows.

## What is implemented
- First-run local AI setup flow in Command with one-click install/retry/defer actions
- Hybrid cloud coding routes:
  - `frontend_design` prefers Gemini 3.1 Pro Preview with GPT-5.4 fallback
  - `backend_ops` prefers GPT-5.4 with Gemini 3.1 Pro Preview fallback
- Full workspace surfaces (specialized layouts, not one generic screen):
  - `Command Center`
  - `Adaptive Survey`
  - `Code` (prompt queue + code agent routes)
  - `Execution Stream`
  - `Memory + Notes`
  - `Workspaces`
  - `Access`
  - `AI Guide`
  - `World Monitor` (embedded dashboard via hosted or local dev endpoint)
  - `System Output`
- Travel and mobility intent is now fully captured inside `Adaptive Survey` (no separate mobility form tab)
- Persistent local state under `%LOCALAPPDATA%/Atlas/Windows/atlas_windows_state_v1.json`
  - encrypted at rest with Windows DPAPI (`CurrentUser` scope)
- Production auth flow: in-app secure WebView2 for Apple/Google/passkey, backend `/v1/auth/me` verification, and encrypted persisted API session cookies
- Resumable queue (queued/running prompts recover after restart)
- Local reasoning path prioritizes Rust sidecar (`atlas-rust-reasoner`) with managed fallback
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
1. Open `/Users/avrohom/Downloads/BlackHaven/windows-app/AtlasMasaWindows/AtlasMasaWindows.csproj` in Visual Studio.
2. Select `x64` for most modern PCs, or `ARM64` for ARM laptops.
3. Press `F5`.

## Build Shareable Installer (Recommended DMG-Style for Windows)
Use the App Installer pipeline as the primary release track. This gives users a one-click install flow and supports update checks.

```powershell
cd /Users/avrohom/Downloads/BlackHaven/windows-app/scripts
.\build-windows-dmg-style-installer.ps1 `
  -Arch x64 `
  -Configuration Release `
  -Version 1.0.0 `
  -AppInstallerBaseUrl "https://downloads.atlasmasa.com/windows/stable/x64/" `
  -SigningThumbprint "<YOUR_CODESIGN_CERT_THUMBPRINT>"
```

The `AppInstallerBaseUrl` should be a stable HTTPS folder URL where you host the `web/` bundle files for that architecture.

Output lands in:
- `/Users/avrohom/Downloads/BlackHaven/windows-app/release/<version>/<arch>/appinstaller/`
- Includes:
  - `web/AtlasMasa-<arch>.appinstaller` (double-click install file)
  - `web/AtlasMasa-<arch>.msix`
  - `web/index.html` (friendly install page with one-click button)
  - `web/Install-AtlasMasa.cmd`
  - `web/INSTALL_LINK.txt` (`ms-appinstaller` deep link)
  - `AtlasMasa-Windows-Install-<version>-<arch>.zip` (Shopify-ready bundle)
  - `SHA256SUMS.txt`
  - `appinstaller-manifest.json`

Production requirements:
- Code-sign certificate (`-SigningThumbprint`) for trusted installs
- Stable HTTPS hosting for the files inside `web/`
- .NET 8 SDK and Rust toolchain (recommended)

Local test build without signing (not for production):

```powershell
.\build-windows-dmg-style-installer.ps1 `
  -Arch x64 `
  -Version 1.0.0 `
  -AppInstallerBaseUrl "https://downloads.atlasmasa.com/windows/stable/x64/" `
  -AllowUnsigned
```

Legacy fallback installer path (`.exe` wizard):

```powershell
.\build-windows-installer.ps1 -Arch x64 -Configuration Release -Version 1.0.0
```

For publish-only (no installer package):

```powershell
cd /Users/avrohom/Downloads/BlackHaven/windows-app/scripts
.\publish-windows.ps1 -Arch x64 -Configuration Release -Version 1.0.0
```

## Rust local reasoner (recommended)
Windows uses Rust first for deterministic local reasoning.

Build the Rust binary:

```bash
cd /Users/avrohom/Downloads/BlackHaven/windows-app/rust-atlas-reasoner
cargo build --release
```

Then point the Windows app to it:

```bash
setx ATLAS_RUST_REASONER_BIN "C:\path\to\atlas-rust-reasoner.exe"
```

If this is not set, Windows will try common local paths and then fall back to managed C# local reasoning.

## Local LLM bridge (Phase 1 production path)
Windows now uses app-managed Ollama as the local runtime contract for end users. The app installer gets the desktop app onto the machine, and first launch continues local AI preparation inside the app.

## Shared backend target
Windows now uses the same Atlas backend base as web + iOS (`https://api.atlasmasa.com`) and can be overridden:
- UI: `Access` tab → `Shared backend API base`
- Env override: `ATLAS_API_BASE` (validated; release builds keep production host allowlist)

Environment variables:
- `ATLAS_LOCAL_LLM_ENABLED` (`true` by default)
- `ATLAS_LOCAL_LLM_ENDPOINT` (default: `http://127.0.0.1:11434/v1/chat/completions`)
- `ATLAS_LOCAL_LLM_MODEL` (default: `qwen2.5:7b,deepseek-r1:14b`; set a fixed model list to override policy)
- `ATLAS_LOCAL_LLM_MODEL_CATALOG` (optional ordered list, comma-separated; heavy to light)
- `ATLAS_RUST_REASONER_BIN` (optional absolute path to `atlas-rust-reasoner.exe`)

Default model packs:
- `Fast Starter` -> `qwen2.5:7b`
- `Balanced Reasoner` -> `deepseek-r1:14b`

Rust policy mode now selects reasoning budget from hardware and helps recommend the starting pack:
- CPU cores + RAM tier
- task type (`queue_reasoning`, `adaptive_question`, etc.)
- configured model override (`ATLAS_LOCAL_LLM_MODEL`)

Shared runtime launcher:

```bash
cd /Users/avrohom/Downloads/BlackHaven
ATLAS_LLM_HF_REPO=unsloth/Qwen2.5-3B-Instruct-GGUF:q4_k_m \
ATLAS_LLM_MODEL_ALIAS=atlas-local-3b \
./scripts/start-local-llm-runtime.sh
```

See `/Users/avrohom/Downloads/BlackHaven/LLM_ROLLOUT.md` for cross-platform rollout details.

## World Monitor integration
Windows includes a dedicated `World Monitor` tab with embedded `WebView2`.

- Hosted preset: `https://worldmonitor.app`
- Local preset: `http://127.0.0.1:5173`
- Custom endpoint: editable URL field in the tab

To run from the added local folder:

```bash
cd /Users/avrohom/Downloads/BlackHaven/worldmonitor-main
npm install
npm run dev
```

Then click `Use Local Dev` in the Windows app.

## Distribution tracks requested
- `Yosef + Benny` Windows track:
  - publish `x64` `Release`
  - produce DMG-style App Installer bundle via `scripts/build-windows-dmg-style-installer.ps1`
- `Yosef + Yasha` Android track:
  - use Android flavor builds (`yosefRelease`, `yashaRelease`) in `/Users/avrohom/Downloads/BlackHaven/android-app`.

## End-user setup promise
- install app
- open app
- choose recommended local AI
- BlackHaven prepares local AI
- app enters Survey/Command when ready

## Shopify Distribution
See:
- `/Users/avrohom/Downloads/BlackHaven/windows-app/docs/SHOPIFY_DISTRIBUTION.md`

## Private Backup Repo (Windows App Only)
Set up automatic backup sync into a dedicated private Git repo:

```bash
chmod +x windows-app/scripts/setup-windows-backup-repo.sh windows-app/scripts/sync-windows-backup.sh
./windows-app/scripts/setup-windows-backup-repo.sh \
  --remote-url git@github.com:YOUR_ORG/YOUR_PRIVATE_WINDOWS_REPO.git \
  --branch main
```

Reference:
- `/Users/avrohom/Downloads/BlackHaven/windows-app/docs/WINDOWS_PRIVATE_BACKUP_REPO.md`

## Performance intent for strong PCs
- Queue concurrency increases automatically on high-core systems.
- ReadyToRun publish is enabled in project settings.
- Server GC + tiered JIT enabled for sustained heavy local use.
