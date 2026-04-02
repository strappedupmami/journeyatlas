import Link from "next/link";
import styles from "../styles.module.css";

const macOSDownloadURL = process.env.NEXT_PUBLIC_BLACKHAVEN_MACOS_DOWNLOAD_URL ?? "";
const windowsDownloadURL = process.env.NEXT_PUBLIC_BLACKHAVEN_WINDOWS_DOWNLOAD_URL ?? "";
const supportEmailEnv = process.env.NEXT_PUBLIC_BLACKHAVEN_SUPPORT_EMAIL ?? "";
const supportEmail = supportEmailEnv || "support@blackhaven.ai";
const docsURL = process.env.NEXT_PUBLIC_BLACKHAVEN_INSTALL_GUIDE_URL ?? "";

const releaseRows = [
  {
    key: "mac",
    title: "BlackHaven for macOS",
    description: "Desktop command center app for Apple Silicon and Intel Macs.",
    requirement: "macOS 13+ recommended",
    url: macOSDownloadURL
  },
  {
    key: "win",
    title: "BlackHaven for Windows",
    description: "Desktop command center app for Windows 11+ systems.",
    requirement: "Windows 11 recommended",
    url: windowsDownloadURL
  }
];

const readinessRows = [
  {
    title: "Installer trust",
    description: "Use real signed installers so macOS Gatekeeper and Windows SmartScreen do not become the onboarding experience."
  },
  {
    title: "Support coverage",
    description: "Have a monitored support inbox and a clear owner for release-day issues, failed model installs, and account problems."
  },
  {
    title: "Setup guidance",
    description: "Publish a real install and recovery guide for users who are not comfortable with runtimes, permissions, or local AI archive/storage demands."
  },
  {
    title: "Release operations",
    description: "Keep versioned release notes, rollback paths, and known-issues documentation so customers are not guessing what changed."
  }
];

const productRows = [
  "Desktop-led command center for macOS and Windows",
  "Execution stream that turns idle moments into the next useful move",
  "Queue-backed reasoning, memory, workspaces, and proactive outputs",
  "Automatic hardware-aware model and context management on desktop",
  "Desktop-side encrypted local archive for durable raw context",
  "Manual-state routing, support guidance, and continuity-aware planning",
  "Interactive checklist hub with notes, links, file references, and progress state",
  "Local activity suggestions and itinerary generation",
  "Research-backed discovery and monitoring surfaces instead of a pure chat-only workflow",
  "Mobile companion flow for capture, check-ins, remote control, and continuity",
  "Cost-threshold AMM that should protect cloud spend before max context is reached",
  "Local hardware budgeting so context and model choices stay inside the user’s computer envelope",
  "Roadmap path toward biometrics, deeper automation, and richer external sync"
];

const ownerChecklistRows = [
  "Publish the real signed installer URLs for macOS and Windows.",
  "Point support to a monitored inbox and assign release-day ownership.",
  "Publish an install guide that covers local AI setup, permissions, archive storage, and recovery.",
  "Document Eco / Balanced / Performance behavior so users understand the quality-cost-hardware tradeoff.",
  "Verify auth, billing, remote pairing, and degraded-internet behavior with clean end-user accounts.",
  "Decide how research and monitoring claims are phrased publicly so the site matches what the apps really surface today.",
  "Do not market biometric-aware resets, automated invites, rich checklist embeds, or external itinerary sync as live until the product can really support them."
];

const envStatusRows = [
  {
    label: "macOS installer URL",
    ready: Boolean(macOSDownloadURL)
  },
  {
    label: "Windows installer URL",
    ready: Boolean(windowsDownloadURL)
  },
  {
    label: "Install guide URL",
    ready: Boolean(docsURL)
  },
  {
    label: "Support inbox",
    ready: Boolean(supportEmailEnv)
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
          This page is the single source for desktop distribution links. BlackHaven is sold as a desktop-led command
          center, so this page has to do more than host buttons: it has to make release trust obvious and explain
          what the larger life/business/travel system already does today, what the desktop apps own locally, and what
          mobile companions rely on the paired desktop to handle.
        </p>
        <div className={styles.heroActions}>
          <Link href="/blackhaven" className={styles.secondary}>
            Back To Website
          </Link>
          <Link href="/blackhaven/readiness" className={styles.secondary}>
            Launch Readiness
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
              <p className={styles.requirementText}>{row.requirement}</p>

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

      <section className={styles.section}>
        <h2>What Users Are Downloading Into</h2>
        <article className={`${styles.card} ${styles.featurePanel}`}>
          <div>
            <p className={styles.panelLabel}>Product model</p>
            <h3>The desktop app is the main BlackHaven experience. Mobile continues the loop away from the desk.</h3>
          </div>
          <ul className={styles.checklist}>
            {productRows.map((row) => (
              <li key={row}>{row}</li>
            ))}
          </ul>
        </article>
      </section>

      <section className={styles.section}>
        <h2>Local AI Cost And Hardware Envelope</h2>
        <div className={styles.grid}>
          <article className={styles.card}>
            <h3>Local-first by default</h3>
            <p>
              BlackHaven should deliver core value on-device first. Users should not need prepaid credits just to get
              memory, queueing, archive direction, or desktop command-center value.
            </p>
          </article>
          <article className={styles.card}>
            <h3>Optional cloud add-on</h3>
            <p>
              Cloud reasoning and coding stay optional and prepaid. The product should compact on projected cost drift
              before a request becomes wasteful, not only when an API limit is almost hit.
            </p>
          </article>
          <article className={styles.card}>
            <h3>Preset-driven control</h3>
            <p>
              Eco, Balanced, and Performance should let the user trade off compaction, response depth, and hardware
              pressure without having to understand every implementation detail.
            </p>
          </article>
          <article className={styles.card}>
            <h3>Hardware-aware honesty</h3>
            <p>
              Users need clear guidance on the machine class, RAM, storage, and power expectations required for the
              local AI experience the website is selling.
            </p>
          </article>
        </div>
      </section>

      <section className={styles.section}>
        <h2>What The Core Enables Next</h2>
        <div className={styles.grid}>
          <article className={styles.card}>
            <h3>Interactive checklist hub</h3>
            <p>
              The same desktop core that already handles memory, queueing, and workspaces now powers project
              checklists with instructions, links, file references, notes, and next-step routing.
            </p>
          </article>
          <article className={styles.card}>
            <h3>Healthier execution support</h3>
            <p>
              BlackHaven now adds supportive reset prompts and better execution conditions while staying honest about
              what is live versus roadmap.
            </p>
          </article>
          <article className={styles.card}>
            <h3>Life and travel intelligence</h3>
            <p>
              The product now includes local activity suggestions and itinerary assistance built on the same
              local-first command-center infrastructure, not a separate thin app.
            </p>
          </article>
          <article className={styles.card}>
            <h3>Desktop-local memory authority</h3>
            <p>
              macOS and Windows are the authority for local archive, memory compaction, and heavier local model work.
              Phones stay in the loop, but they do not pretend to replace the desktop vault.
            </p>
          </article>
        </div>
      </section>

      <section className={styles.section}>
        <h2>End-User Readiness Checklist</h2>
        <p className={styles.sectionIntro}>
          This page now doubles as the operational handoff view for launch readiness, not just a pair of download
          buttons.
        </p>
        <div className={styles.grid}>
          {readinessRows.map((row) => (
            <article key={row.title} className={styles.card}>
              <h3>{row.title}</h3>
              <p>{row.description}</p>
            </article>
          ))}
          <article className={styles.card}>
            <h3>Distribution</h3>
            <p>Point both download buttons to the real signed installers you want customers to use.</p>
          </article>
          <article className={styles.card}>
            <h3>Support Path</h3>
            <p>Make sure support requests route to a real inbox: {supportEmail}.</p>
          </article>
          <article className={styles.card}>
            <h3>Install Guidance</h3>
            <p>
              {docsURL
                ? "An install guide link is configured for users who need setup help."
                : "Add an install guide URL before broad distribution."}
            </p>
          </article>
          <article className={styles.card}>
            <h3>Roadmap honesty</h3>
            <p>
              Keep “live now” and “next layer” clearly separated so users know which manual-state, checklist, and
              itinerary features are already in product, which desktop-local memory protections are live, and which
              deeper automations are still being built.
            </p>
          </article>
        </div>

        <article className={`${styles.card} ${styles.featurePanel}`}>
          <div>
            <p className={styles.panelLabel}>Current config status</p>
            <h3>These checks reflect what the website can see right now from environment-backed release settings.</h3>
          </div>
          <ul className={styles.checklist}>
            {envStatusRows.map((row) => (
              <li key={row.label}>
                {row.label}: {row.ready ? "configured" : "missing"}
              </li>
            ))}
          </ul>
        </article>

        <div className={styles.heroActions}>
          {docsURL ? (
            <a className={styles.secondary} href={docsURL}>
              Open Install Guide
            </a>
          ) : null}
          <Link href="/blackhaven/readiness" className={styles.secondary}>
            Full Readiness Checklist
          </Link>
        </div>
      </section>

      <section className={styles.section}>
        <h2>Owner-Side Launch Blockers</h2>
        <article className={styles.card}>
          <ul>
            {ownerChecklistRows.map((row) => (
              <li key={row}>{row}</li>
            ))}
          </ul>
        </article>
      </section>

      <section className={styles.banner}>
        This downloads page is the canonical BlackHaven desktop entry point, while legacy Atlas pages remain secondary.
      </section>
    </div>
  );
}
