# Slow Load Monitoring (Web + Native)

## What this does
- Browser monitor in the Next.js app flags slow page loads (default threshold: `4500ms`).
- iOS, macOS, and Android API clients now report slow backend calls (default threshold: `4500ms`).
- Client sends a small diagnostics payload to `POST /api/ops/slow-load`.
- Server logs a structured incident with an `incidentId`.
- Optional webhook forwarding can push incidents into your alerting or ticket pipeline.

## Environment setup

Client-side (optional):

```bash
NEXT_PUBLIC_SLOW_LOAD_THRESHOLD_MS=4500
NEXT_PUBLIC_SLOW_LOAD_ENDPOINT=/api/ops/slow-load
```

Server-side (optional):

```bash
ATLAS_SLOW_LOAD_WEBHOOK_URL=https://<your-alert-endpoint>
ATLAS_SLOW_LOAD_WEBHOOK_BEARER_TOKEN=<token-if-needed>
```

## Payload shape (summary)
- `kind`: `navigation`, `route-paint`, or `network-request`
- `url`, `referrer`, `userAgent`, `timestamp`
- `thresholdMs`
- `metrics` (ms values only)
- `connection` (if browser exposes network hints)
- optional native fields: `method`, `error`

## Native endpoint routing
- Production native apps report to: `https://atlasmasa.com/api/ops/slow-load`
- Localhost native builds report to: `http://localhost:3000/api/ops/slow-load` (or `https://localhost:3000/...` if your base URL uses TLS)

## What you need to do on your end
1. Set `ATLAS_SLOW_LOAD_WEBHOOK_URL` to your incident intake (Slack webhook, PagerDuty event bridge, or ticket webhook).
2. Add a routing rule so every incident opens a single triage thread with `incidentId`.
3. Include these fields in the alert message: `incidentId`, `kind`, `url`, `metrics`, `receivedAt`.
4. Share the incident payload or ID in this workspace thread; I can then patch the relevant code path and return exact fix steps.

## Local verification

Run from repo root:

```bash
npm run dev
```

Open a page with intentional CPU throttling / slow network and confirm:
- `POST /api/ops/slow-load` returns `{ ok: true, incidentId }`
- server logs include `[atlas-slow-load]` plus incident JSON.
