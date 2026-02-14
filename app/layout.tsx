import type { Metadata } from "next";
import { Rubik, Assistant } from "next/font/google";
import { SiteFooter } from "@/components/SiteFooter";
import { SiteHeader } from "@/components/SiteHeader";
import { SITE_DESCRIPTION, SITE_INDEXABLE } from "@/lib/site";
import "./globals.css";

const rubik = Rubik({
  subsets: ["hebrew", "latin"],
  variable: "--font-display",
  weight: ["400", "500", "700"]
});

const assistant = Assistant({
  subsets: ["hebrew", "latin"],
  variable: "--font-body",
  weight: ["400", "600", "700"]
});

export const metadata: Metadata = {
  title: "אטלס מסע | חופשה בלי מלונות",
  description: SITE_DESCRIPTION,
  robots: {
    index: SITE_INDEXABLE,
    follow: SITE_INDEXABLE
  }
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="he" dir="rtl">
      <body className={`${rubik.variable} ${assistant.variable}`}>
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
