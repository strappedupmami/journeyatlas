import type { Metadata } from "next";
import Link from "next/link";
import styles from "./styles.module.css";

export const metadata: Metadata = {
  title: "BlackHaven | Command Center + Desktop Apps",
  description:
    "BlackHaven is the command-center operating system for life and business execution, with desktop apps for macOS and Windows."
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
            <Link href="/blackhaven#command-center">Command Center</Link>
            <Link href="/blackhaven#desktop">Desktop Apps</Link>
            <Link href="/blackhaven#operations">Operations</Link>
            <Link href="/blackhaven/downloads" className={styles.navCta}>
              Downloads
            </Link>
          </nav>
        </div>
      </header>

      <div className={styles.shell}>{children}</div>

      <footer className={styles.footer}>
        <div className={styles.shell}>
          <p>BlackHaven is separate from Atlas Masa and focuses on AI command-center software.</p>
          <p>{new Date().getFullYear()} © BlackHaven</p>
        </div>
      </footer>
    </div>
  );
}
