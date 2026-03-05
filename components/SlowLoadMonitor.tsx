"use client";

import { useEffect, useMemo, useRef } from "react";
import { usePathname, useSearchParams } from "next/navigation";

const DEFAULT_THRESHOLD_MS = 4500;
const DEFAULT_ENDPOINT = "/api/ops/slow-load";

type SlowLoadKind = "navigation" | "route-paint";

type SlowLoadEvent = {
  kind: SlowLoadKind;
  source: "next-web";
  url: string;
  referrer: string;
  userAgent: string;
  timestamp: string;
  thresholdMs: number;
  metrics: Record<string, number>;
  connection?: {
    effectiveType?: string;
    downlinkMbps?: number;
    rttMs?: number;
    saveData?: boolean;
  };
};

type BrowserConnection = {
  effectiveType?: string;
  downlink?: number;
  rtt?: number;
  saveData?: boolean;
};

function getThresholdMs(): number {
  const raw = Number(process.env.NEXT_PUBLIC_SLOW_LOAD_THRESHOLD_MS ?? DEFAULT_THRESHOLD_MS);
  if (!Number.isFinite(raw) || raw <= 0) {
    return DEFAULT_THRESHOLD_MS;
  }
  return Math.round(raw);
}

function buildUrl(pathname: string, query: string): string {
  if (!query) {
    return pathname;
  }
  return `${pathname}?${query}`;
}

function toMetric(value: number | undefined): number | undefined {
  if (value === undefined || !Number.isFinite(value)) {
    return undefined;
  }
  return Math.round(value);
}

function pickConnection(): SlowLoadEvent["connection"] | undefined {
  const connection = (navigator as Navigator & { connection?: BrowserConnection }).connection;
  if (!connection) {
    return undefined;
  }
  return {
    effectiveType: connection.effectiveType,
    downlinkMbps: toMetric(connection.downlink),
    rttMs: toMetric(connection.rtt),
    saveData: connection.saveData
  };
}

function sendSlowLoad(endpoint: string, payload: SlowLoadEvent): void {
  const body = JSON.stringify(payload);
  if (typeof navigator.sendBeacon === "function") {
    const sent = navigator.sendBeacon(endpoint, new Blob([body], { type: "application/json" }));
    if (sent) {
      return;
    }
  }
  void fetch(endpoint, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body,
    keepalive: true
  }).catch(() => {
    // Silent failure by design: diagnostics should never block UX.
  });
}

export function SlowLoadMonitor() {
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const didReportNavigation = useRef(false);

  const routeUrl = useMemo(() => buildUrl(pathname, searchParams.toString()), [pathname, searchParams]);

  useEffect(() => {
    const thresholdMs = getThresholdMs();
    const endpoint = process.env.NEXT_PUBLIC_SLOW_LOAD_ENDPOINT ?? DEFAULT_ENDPOINT;

    const basePayload = {
      source: "next-web" as const,
      url: window.location.href,
      referrer: document.referrer,
      userAgent: navigator.userAgent,
      timestamp: new Date().toISOString(),
      thresholdMs,
      connection: pickConnection()
    };

    const report = (kind: SlowLoadKind, metrics: Record<string, number>) => {
      sendSlowLoad(endpoint, { ...basePayload, kind, metrics });
    };

    const routePaintStart = performance.now();
    const routePaintRaf = window.requestAnimationFrame(() => {
      const routePaintMs = performance.now() - routePaintStart;
      if (routePaintMs >= thresholdMs) {
        report("route-paint", {
          routePaintMs: Math.round(routePaintMs)
        });
      }
    });

    let loadHandler: (() => void) | null = null;

    if (!didReportNavigation.current) {
      const evaluateNavigation = () => {
        const nav = performance.getEntriesByType("navigation")[0] as PerformanceNavigationTiming | undefined;
        if (!nav) {
          return;
        }

        const fcp = performance.getEntriesByName("first-contentful-paint")[0]?.startTime;
        const lcpEntries = performance.getEntriesByType("largest-contentful-paint");
        const lcp = lcpEntries[lcpEntries.length - 1]?.startTime;
        const loadMs = nav.loadEventEnd > 0 ? nav.loadEventEnd : performance.now();
        const slowestMetric = Math.max(loadMs, nav.domContentLoadedEventEnd, lcp ?? 0, fcp ?? 0);

        if (slowestMetric < thresholdMs) {
          return;
        }

        report("navigation", {
          loadEventEndMs: Math.round(loadMs),
          domContentLoadedMs: Math.round(nav.domContentLoadedEventEnd),
          responseStartMs: Math.round(nav.responseStart),
          firstContentfulPaintMs: toMetric(fcp) ?? -1,
          largestContentfulPaintMs: toMetric(lcp) ?? -1
        });
        didReportNavigation.current = true;
      };

      if (document.readyState === "complete") {
        window.setTimeout(evaluateNavigation, 0);
      } else {
        loadHandler = evaluateNavigation;
        window.addEventListener("load", evaluateNavigation, { once: true });
      }
    }

    return () => {
      window.cancelAnimationFrame(routePaintRaf);
      if (loadHandler) {
        window.removeEventListener("load", loadHandler);
      }
    };
  }, [routeUrl]);

  return null;
}
