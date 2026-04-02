import type { Metadata } from "next";
import Link from "next/link";
import { SITE_URL, getMetadataBase } from "@/lib/site";
import styles from "./styles.module.css";

export const metadata: Metadata = {
  metadataBase: getMetadataBase(),
  title: "BlackHaven | Execution-First Life + Business + Travel AI",
  description:
    "BlackHaven is the desktop-first, local-memory command center for life, business, and travel: macOS and Windows run the full local AI, encrypted archive, AMM-aware compute budgeting, and continuity workflows while mobile companions keep capture and control alive away from the desk.",
  alternates: {
    canonical: "/blackhaven"
  },
  openGraph: {
    type: "website",
    url: `${SITE_URL}/blackhaven`,
    title: "BlackHaven | Execution-First Life + Business + Travel AI",
    description:
      "BlackHaven is the desktop-first, local-memory command center for life, business, and travel: macOS and Windows run the full local AI, encrypted archive, AMM-aware compute budgeting, and continuity workflows while mobile companions keep capture and control alive away from the desk.",
    siteName: "BlackHaven"
  }
};

export default function BlackHavenLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className={styles.site} dir="ltr">
      <header className={styles.topbar}>
        <div className={styles.shell}>
          <Link href="/blackhaven" className={styles.brand}>
            <span className={styles.brandDot} aria-hidden>
              BH
            </span>
            <span>
              BlackHaven
              <small>Command Center OS</small>
            </span>
          </Link>

          <nav className={styles.nav} aria-label="BlackHaven">
            <Link href="/blackhaven#how-it-works">How It Works</Link>
            <Link href="/blackhaven#app-suite">App Suite</Link>
            <Link href="/blackhaven#state-aware">State-Aware</Link>
            <Link href="/blackhaven#compute-economics">Compute</Link>
            <Link href="/blackhaven#hardware-budgeting">Hardware</Link>
            <Link href="/blackhaven#checklists">Checklists</Link>
            <Link href="/blackhaven#travel-intelligence">Travel</Link>
            <Link href="/blackhaven#research">Research</Link>
            <Link href="/blackhaven#healthy-wealthy">Support</Link>
            <Link href="/blackhaven#governance">Governance</Link>
            <Link href="/blackhaven#live-now">Live Vs Next</Link>
            <Link href="/blackhaven#desktop">Desktop Apps</Link>
            <Link href="/blackhaven#infrastructure">Resilience Proof</Link>
            <Link href="/blackhaven#readiness">Readiness</Link>
            <Link href="/blackhaven/readiness">Checklist</Link>
            <Link href="/blackhaven/downloads" className={styles.navCta}>
              Downloads
            </Link>
          </nav>
        </div>
      </header>

      <div className={styles.shell}>{children}</div>

      <footer className={styles.footer}>
        <div className={styles.shell}>
          <p>BlackHaven is the umbrella product story for the desktop command center, local memory vault, and companion-device workflow across the apps in this repo.</p>
          <p>{new Date().getFullYear()} © BlackHaven</p>
        </div>
      </footer>
    </div>
  );
}
