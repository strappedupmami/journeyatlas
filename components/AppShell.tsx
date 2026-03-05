"use client";

import { usePathname } from "next/navigation";
import { SiteFooter } from "@/components/SiteFooter";
import { SiteHeader } from "@/components/SiteHeader";

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const isBlackHavenSite = pathname.startsWith("/blackhaven");

  return (
    <>
      <a href="#main-content" className="skip-link">
        דלג לתוכן הראשי
      </a>
      {!isBlackHavenSite && <SiteHeader />}
      <main id="main-content">{children}</main>
      {!isBlackHavenSite && <SiteFooter />}
    </>
  );
}
