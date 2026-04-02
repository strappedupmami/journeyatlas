import Link from "next/link";
import styles from "../styles.module.css";

const builtNowRows = [
  "Native product surfaces for survey, memory, queueing, workspaces, remote control, and proactive execution already exist across the apps in this repo.",
  "Manual state-aware execution routing, supportive reset guidance, local checklist generation, and local activity/itinerary generation now exist in the desktop apps.",
  "Research-backed discovery, evidence-oriented execution framing, and monitoring surfaces are already part of the app story rather than a pure future concept.",
  "The BlackHaven website now leads with a broader life/business/travel execution story while grounding it in desktop-local AI, encrypted archive, remote-desktop, and resilience reality.",
  "The downloads hub is already env-driven, so release links can be swapped without rewriting the website.",
  "The product model already supports local-first value with optional prepaid cloud add-ons instead of forcing cloud usage for core utility.",
  "The backend now has structured settings space for compute mode, response depth, memory depth, and AMM-style guardrails."
];

const opsReadyRows = [
  "BlackHaven now has a dedicated website route, downloads hub, and readiness page that all tell the same desktop-first product story.",
  "Launch messaging can now frame local AI economics and hardware expectations without hiding the optional cloud layer.",
  "The website copy now separates current app truth from future-facing automation more clearly than before."
];

const ownerActionRows = [
  "Publish the actual signed macOS and Windows installers and set the public download URLs.",
  "Point support to a monitored inbox and publish a real install guide.",
  "Verify production auth, billing, and backend flows with clean end-user accounts.",
  "Publish privacy, terms, and any refund/subscription language implied by the app experience.",
  "Run real-world install, local AI setup, local archive growth, remote pairing, LAN reachability, and degraded-internet tests on target hardware.",
  "Document minimum disk, RAM, and power expectations for end users who want the local AI, archive, and continuity features.",
  "Decide the exact AMM / Eco-Balanced-Performance defaults you want to present to end users for launch.",
  "Publish how research and monitoring features should be described publicly so evidence-backed assistance is not exaggerated into medical or fully autonomous claims.",
  "Publish an explicit live-now versus roadmap boundary for biometric-aware resets, social support automation, rich checklist embeds, and external itinerary sync.",
  "Review whether future state-aware inputs create extra privacy or consent requirements before those features are marketed as live."
];

const releaseFlowRows = [
  {
    title: "Find",
    description: "Users need one stable page with trusted installers, versioning, and system requirements."
  },
  {
    title: "Install",
    description: "Signed builds and OS-specific guidance need to prevent trust warnings from becoming the onboarding experience."
  },
  {
    title: "Activate",
    description: "Sign-in, billing unlocks, and local AI setup should complete without manual founder intervention."
  },
  {
    title: "Operate",
    description: "Support, recovery docs, and honest confidence signaling need to hold up outside demos and developer machines."
  },
  {
    title: "Expand",
    description: "Only widen the promise to health-aware support, checklist automation, or itinerary intelligence when product truth, privacy coverage, and support readiness are all in place."
  }
];

const promiseRows = [
  {
    title: "Sell The Right Product",
    description: "Users should understand that BlackHaven is a desktop-led execution system, not just a chat app with local AI attached."
  },
  {
    title: "Make The First Hour Work",
    description: "Install, sign-in, local AI setup, and first useful execution-stream output need to happen without founder rescue."
  },
  {
    title: "Keep Trust Intact",
    description: "The website, installers, support path, and in-app state all need to tell the same truth about what is live, local, encrypted, estimated, or still operator-controlled."
  },
  {
    title: "Protect The Honesty Boundary",
    description: "Roadmap-first marketing works only if future-aware features are framed as the next layer and not quietly sold as present-day functionality."
  }
];

export default function BlackHavenReadinessPage() {
  return (
    <div className={styles.page}>
      <section className={styles.hero}>
        <p className={styles.kicker}>Launch Readiness</p>
        <h1>
          BlackHaven is <span>code-ready in key layers</span> and still needs a few owner-side pieces before broad release.
        </h1>
        <p>
          This page turns the PDF’s “end-user readiness / real-world functionality” requirement into a practical
          checkpoint so the product narrative and the operational truth stay aligned across current capabilities and
          the remaining roadmap layer.
        </p>
        <div className={styles.heroActions}>
          <Link href="/blackhaven/downloads" className={styles.primary}>
            Open Downloads Hub
          </Link>
          <Link href="/blackhaven" className={styles.secondary}>
            Back To Website
          </Link>
        </div>
      </section>

      <section className={styles.section}>
        <h2>Code-Ready Now</h2>
        <article className={styles.card}>
          <ul>
            {builtNowRows.map((row) => (
              <li key={row}>{row}</li>
            ))}
          </ul>
        </article>
      </section>

      <section className={styles.section}>
        <h2>Ops-Ready Framing</h2>
        <article className={styles.card}>
          <ul>
            {opsReadyRows.map((row) => (
              <li key={row}>{row}</li>
            ))}
          </ul>
        </article>
      </section>

      <section className={styles.section}>
        <h2>Still Needs Your Action</h2>
        <article className={styles.card}>
          <ul>
            {ownerActionRows.map((row) => (
              <li key={row}>{row}</li>
            ))}
          </ul>
        </article>
      </section>

      <section className={styles.section}>
        <h2>Customer Promise At Launch</h2>
        <div className={styles.grid}>
          {promiseRows.map((row) => (
            <article key={row.title} className={styles.card}>
              <h3>{row.title}</h3>
              <p>{row.description}</p>
            </article>
          ))}
        </div>
      </section>

      <section className={styles.section}>
        <h2>End-User Release Flow</h2>
        <div className={styles.grid}>
          {releaseFlowRows.map((row) => (
            <article key={row.title} className={styles.card}>
              <h3>{row.title}</h3>
              <p>{row.description}</p>
            </article>
          ))}
        </div>
      </section>

      <section className={styles.banner}>
        Broad launch should wait until installers, support, legal/privacy coverage, production auth/billing,
        real-device testing, local archive behavior, and the live-versus-roadmap boundary are all verified together.
      </section>
    </div>
  );
}
