# Local Concierge Quickstart

## 1) Start concierge API
From project root:

```bash
./scripts/start-concierge-local.sh
```

Expected:
- API on `http://localhost:8080`
- default API key: `dev-atlas-key`

## 2) Open UI
Open directly:
- `/Users/avrohom/Downloads/journeyatlas/homepage/concierge-local.html`

Recommended (avoids Safari `Load failed` issues from `file://`):

```bash
./scripts/serve-homepage-local.sh
```

Then open:
- `http://localhost:5500/concierge-local.html`

## 3) First tests
In the UI:
1. Click `בדיקת שירות`
2. Ask: `תכנן לי סופ״ש חופים עם שגרת מים/אפור`
3. Switch to `תכנון מסלול`, choose style + days, click send

## 4) If it fails
- Make sure Rust/cargo is installed (`cargo --version`).
- Make sure API process is still running.
- Confirm API base in advanced settings is `http://localhost:8080`.
- If you changed `ATLAS_API_KEY`, update key in advanced settings.
- If Safari shows `Load failed`, run both scripts:
  1. `./scripts/start-concierge-local.sh`
  2. `./scripts/serve-homepage-local.sh`
  and use `http://localhost:5500/concierge-local.html` instead of opening the file directly.
