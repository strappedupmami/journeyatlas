import type { Metadata } from "next";
import { SiteFooter } from "@/components/SiteFooter";
import { SiteHeader } from "@/components/SiteHeader";
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
        <a href="#main-content" className="skip-link">
          דלג לתוכן הראשי
        </a>
        <SiteHeader />
        <main id="main-content">{children}</main>
        <SiteFooter />
      </body>
    </html>
  );
}
