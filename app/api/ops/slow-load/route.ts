import { randomUUID } from "node:crypto";
import { NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const MAX_TEXT = 300;
const MAX_METRICS = 20;

type SlowLoadKind = "navigation" | "route-paint" | "network-request";

type SlowLoadPayload = {
  kind: SlowLoadKind;
  source: string;
  url: string;
  referrer: string;
  userAgent: string;
  timestamp: string;
  thresholdMs: number;
  metrics: Record<string, number>;
  method?: string;
  error?: string;
  connection?: {
    effectiveType?: string;
    downlinkMbps?: number;
    rttMs?: number;
    saveData?: boolean;
  };
};

function cleanText(value: unknown): string {
  if (typeof value !== "string") {
    return "";
  }
  return value.slice(0, MAX_TEXT);
}

function cleanOptionalText(value: unknown): string | undefined {
  const text = cleanText(value).trim();
  return text.length > 0 ? text : undefined;
}

function cleanMs(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return null;
  }
  if (value < 0) {
    return 0;
  }
  if (value > 120000) {
    return 120000;
  }
  return Math.round(value);
}

function cleanMetrics(value: unknown): Record<string, number> {
  if (!value || typeof value !== "object") {
    return {};
  }
  const entries = Object.entries(value as Record<string, unknown>).slice(0, MAX_METRICS);
  const result: Record<string, number> = {};
  for (const [key, metric] of entries) {
    if (!/^[a-zA-Z0-9_-]{1,40}$/.test(key)) {
      continue;
    }
    const cleanValue = cleanMs(metric);
    if (cleanValue === null) {
      continue;
    }
    result[key] = cleanValue;
  }
  return result;
}

function parseBody(raw: unknown): SlowLoadPayload | null {
  if (!raw || typeof raw !== "object") {
    return null;
  }
  const body = raw as Record<string, unknown>;
  const kind = body.kind === "navigation" || body.kind === "route-paint" || body.kind === "network-request"
    ? body.kind
    : null;
  if (!kind) {
    return null;
  }
  const thresholdMs = cleanMs(body.thresholdMs);
  if (thresholdMs === null) {
    return null;
  }
  return {
    kind,
    source: cleanText(body.source),
    url: cleanText(body.url),
    referrer: cleanText(body.referrer),
    userAgent: cleanText(body.userAgent),
    timestamp: cleanText(body.timestamp),
    thresholdMs,
    metrics: cleanMetrics(body.metrics),
    method: cleanOptionalText(body.method),
    error: cleanOptionalText(body.error),
    connection: body.connection && typeof body.connection === "object"
      ? {
          effectiveType: cleanText((body.connection as Record<string, unknown>).effectiveType),
          downlinkMbps: cleanMs((body.connection as Record<string, unknown>).downlinkMbps) ?? undefined,
          rttMs: cleanMs((body.connection as Record<string, unknown>).rttMs) ?? undefined,
          saveData: Boolean((body.connection as Record<string, unknown>).saveData)
        }
      : undefined
  };
}

async function forwardToWebhook(incident: Record<string, unknown>): Promise<void> {
  const webhookUrl = process.env.ATLAS_SLOW_LOAD_WEBHOOK_URL;
  if (!webhookUrl) {
    return;
  }
  const authToken = process.env.ATLAS_SLOW_LOAD_WEBHOOK_BEARER_TOKEN;
  try {
    const headers: Record<string, string> = { "content-type": "application/json" };
    if (authToken) {
      headers.authorization = `Bearer ${authToken}`;
    }
    await fetch(webhookUrl, {
      method: "POST",
      headers,
      body: JSON.stringify(incident)
    });
  } catch {
    // Silent failure by design. Primary signal is still app logs.
  }
}

export async function POST(request: Request) {
  let rawBody: unknown;
  try {
    rawBody = await request.json();
  } catch {
    return NextResponse.json({ ok: false, error: "invalid_json" }, { status: 400 });
  }

  const payload = parseBody(rawBody);
  if (!payload) {
    return NextResponse.json({ ok: false, error: "invalid_payload" }, { status: 422 });
  }

  const incidentId = `sli_${Date.now().toString(36)}_${randomUUID().slice(0, 8)}`;
  const ip = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";

  const incident = {
    incidentId,
    event: "slow-load-detected",
    receivedAt: new Date().toISOString(),
    ip,
    ...payload
  };

  console.warn(`[atlas-slow-load] ${JSON.stringify(incident)}`);
  await forwardToWebhook(incident);

  return NextResponse.json({
    ok: true,
    incidentId
  });
}
