import Link from "next/link";
import styles from "./styles.module.css";

const commandCenterCapabilities = [
  {
    title: "Command Center",
    description:
      "One operator surface for planning, delegation, and execution streams across business and life operations."
  },
  {
    title: "Concierge + Workspaces",
    description:
      "Mission chat plus project lanes that track context, priorities, and evolving execution constraints."
  },
  {
    title: "Execution Checklists",
    description:
      "Actionable tasks you can check off, reopen, and update with done/not-done detail for model adjustment."
  },
  {
    title: "World + Market Monitoring",
    description:
      "Always-on intelligence views to support operational decisions with changing geopolitical and market signals."
  }
];

const operationsTargets = [
  "Business operations and growth workflows",
  "Travel and mobility orchestration",
  "Knowledge and memory workflows",
  "Desktop-first agentic execution"
];

export default function BlackHavenHomePage() {
  return (
    <div className={styles.page}>
      <section className={styles.hero}>
        <p className={styles.kicker}>New Product Site</p>
        <h1>
          BlackHaven is the <span>AI command center</span> for modern execution.
        </h1>
        <p>
          This website is intentionally separate from Atlas Masa. Atlas Masa is your Israeli mobile-home company,
          while BlackHaven is the software platform for command center workflows and desktop AI operations.
        </p>
        <div className={styles.heroActions}>
          <Link href="/blackhaven/downloads" className={styles.primary}>
            Desktop Downloads
          </Link>
          <Link href="#command-center" className={styles.secondary}>
            Explore Command Center
          </Link>
        </div>
      </section>

      <section id="command-center" className={styles.section}>
        <h2>Command Center Narrative</h2>
        <p className={styles.sectionIntro}>
          BlackHaven unifies execution planning, proactive intelligence, and agent workflows in one desktop-native
          operating surface.
        </p>
        <div className={styles.grid}>
          {commandCenterCapabilities.map((capability) => (
            <article key={capability.title} className={styles.card}>
              <h3>{capability.title}</h3>
              <p>{capability.description}</p>
            </article>
          ))}
        </div>
      </section>

      <section id="desktop" className={styles.section}>
        <h2>Desktop App Downloads</h2>
        <p className={styles.sectionIntro}>
          Download links for macOS and Windows live on the dedicated downloads page so release links can be swapped
          without changing the command center messaging page.
        </p>
        <article className={`${styles.card} ${styles.downloadCard}`}>
          <div className={styles.downloadMeta}>
            <span className={styles.pill}>macOS</span>
            <span className={styles.pill}>Windows</span>
            <span className={styles.pill}>Desktop Builds</span>
          </div>
          <p>
            Keep all desktop distribution links in one place and point users here from marketing, docs, and in-app
            onboarding.
          </p>
          <Link href="/blackhaven/downloads" className={styles.primary}>
            Open Downloads Hub
          </Link>
        </article>
      </section>

      <section id="operations" className={styles.section}>
        <h2>Operational Scope</h2>
        <p className={styles.sectionIntro}>Initial BlackHaven scope for the website and product narrative:</p>
        <div className={styles.card}>
          <ul>
            {operationsTargets.map((target) => (
              <li key={target}>{target}</li>
            ))}
          </ul>
        </div>
      </section>

      <section className={styles.banner}>
        Atlas Masa and BlackHaven now have clean product separation: different brand, different website narrative,
        different call-to-actions.
      </section>
    </div>
  );
}
