import type { Metadata } from "next";
import { Suspense } from "react";
import { AppShell } from "@/components/AppShell";
import { SlowLoadMonitor } from "@/components/SlowLoadMonitor";
import { SITE_DESCRIPTION, SITE_INDEXABLE } from "@/lib/site";
import "./globals.css";

export const metadata: Metadata = {
  title: "אטלס | חופשה בלי מלונות",
  description: SITE_DESCRIPTION,
  robots: {
    index: SITE_INDEXABLE,
    follow: SITE_INDEXABLE
  }
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="he" dir="rtl">
      <body>
        <Suspense fallback={null}>
          <SlowLoadMonitor />
        </Suspense>
        <Suspense fallback={children}>
          <AppShell>{children}</AppShell>
        </Suspense>
      </body>
    </html>
  );
}
