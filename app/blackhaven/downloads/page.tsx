import Link from "next/link";
import styles from "../styles.module.css";

const macOSDownloadURL = process.env.NEXT_PUBLIC_BLACKHAVEN_MACOS_DOWNLOAD_URL ?? "";
const windowsDownloadURL = process.env.NEXT_PUBLIC_BLACKHAVEN_WINDOWS_DOWNLOAD_URL ?? "";

const releaseRows = [
  {
    key: "mac",
    title: "BlackHaven for macOS",
    description: "Desktop command center app for Apple Silicon and Intel Macs.",
    url: macOSDownloadURL
  },
  {
    key: "win",
    title: "BlackHaven for Windows",
    description: "Desktop command center app for Windows 11+ systems.",
    url: windowsDownloadURL
  }
];

export default function BlackHavenDownloadsPage() {
  return (
    <div className={styles.page}>
      <section className={styles.hero}>
        <p className={styles.kicker}>Desktop Distribution</p>
        <h1>
          BlackHaven <span>Downloads Hub</span>
        </h1>
        <p>
          This page is the single source for desktop distribution links. When a new build is ready, update env vars and
          deploy.
        </p>
        <div className={styles.heroActions}>
          <Link href="/blackhaven" className={styles.secondary}>
            Back To Website
          </Link>
        </div>
      </section>

      <section className={styles.section}>
        <h2>Release Links</h2>
        <p className={styles.sectionIntro}>
          Configure release URLs with `NEXT_PUBLIC_BLACKHAVEN_MACOS_DOWNLOAD_URL` and
          `NEXT_PUBLIC_BLACKHAVEN_WINDOWS_DOWNLOAD_URL`.
        </p>

        <div className={styles.downloadTable}>
          {releaseRows.map((row) => (
            <article key={row.key} className={styles.downloadRow}>
              <div className={styles.downloadRowTop}>
                <h3>{row.title}</h3>
                <span className={styles.pill}>{row.url ? "Live" : "Pending"}</span>
              </div>
              <p>{row.description}</p>

              {row.url ? (
                <a className={styles.primary} href={row.url}>
                  Download Now
                </a>
              ) : (
                <span className={styles.disabledCta}>Link slot ready. Add release URL.</span>
              )}
            </article>
          ))}
        </div>
      </section>

      <section className={styles.banner}>
        This downloads page is BlackHaven-only and intentionally separate from Atlas Masa web flows.
      </section>
    </div>
  );
}
