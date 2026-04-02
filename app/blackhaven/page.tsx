import Link from "next/link";
import styles from "./styles.module.css";

const heroSignals = [
  "Life + business + travel",
  "Desktop-led + mobile companions",
  "Local-first AI",
  "Encrypted local archive",
  "Hardware-aware runtime management",
  "Roadmap-first honesty"
];

const appSurfaceRows = [
  {
    title: "macOS Command Center",
    description:
      "The Mac app is a full local-memory workstation: queue execution, workspace context, encrypted archive, model downloads, remote continuity, and higher-context planning all live here."
  },
  {
    title: "Windows Command Center",
    description:
      "The Windows app is the same desktop authority for local AI, hardware-aware model selection, encrypted archive, resumable queueing, and remote desktop continuity."
  },
  {
    title: "iPhone Companion",
    description:
      "iPhone is the fast companion surface for capture, check-ins, and control while the paired desktop remains the local-memory authority for heavier archive and compaction work."
  },
  {
    title: "Android Companion",
    description:
      "Android extends capture, continuity, and remote reachability without pretending the phone should carry the full local-memory vault by itself."
  }
];

const productSplitRows = [
  {
    title: "Desktop command centers",
    description:
      "macOS and Windows are the authority for local-memory retention, encrypted archive direction, queue-backed reasoning, runtime preparation, hardware-aware model sizing, and heavier continuity work."
  },
  {
    title: "Companion mobile layer",
    description:
      "iPhone and Android keep capture, check-ins, remote control, and continuity alive away from the desk without pretending the phone should hold the full archive vault."
  },
  {
    title: "Local-first core",
    description:
      "The main value layer is local: memory, archive, execution routing, prompt queueing, and hardware-aware model/runtime selection continue working before optional cloud upgrades enter the picture."
  },
  {
    title: "Optional cloud add-on",
    description:
      "Cloud coding and heavier provider-backed reasoning remain optional, prepaid, and explicitly metered. Users are not supposed to buy cloud usage just to get the core product value."
  }
];

const appLoopRows = [
  {
    title: "Profile The Operator",
    description:
      "Adaptive survey, check-ins, and notes capture how the user actually works: pressure, energy, priorities, blockers, and recovery conditions."
  },
  {
    title: "Build Durable Context",
    description:
      "Memory, notes, and workspaces preserve what matters across sessions so the app can stop re-learning the same person and projects every day."
  },
  {
    title: "Route The Next Move",
    description:
      "The execution stream and prompt queue turn context into action: proactive tasks, follow-ups, guided prompts, and heavier queue-backed reasoning when needed."
  },
  {
    title: "Keep A Desktop Home Base",
    description:
      "A plugged-in Mac or Windows machine becomes the continuity node for local AI, remote desktop control, file handoff, and long-running work."
  },
  {
    title: "Carry It On Companion Devices",
    description:
      "iPhone and Android keep the loop alive for capture, check-ins, quick control, and continuity while the desktop stays the main command center."
  }
];

const stateRows = [
  {
    title: "Short Idle Window",
    description:
      "When the user has five minutes, BlackHaven can surface one sharp move instead of another blank input: review a draft, approve a change, clear a blocker, or send the next outreach."
  },
  {
    title: "Deep-Work Window",
    description:
      "When energy is high, the stream can protect heavy work: coding, queue-backed reasoning, long-form drafting, planning, and high-consequence decisions."
  },
  {
    title: "Low-Energy State",
    description:
      "When cognition is drained, BlackHaven can pivot into recovery-safe execution: summaries, cleanup, lighter approvals, and compounding admin that still moves life or business forward."
  },
  {
    title: "High-Friction Stall",
    description:
      "When a build or task is getting stuck, the product can suggest environment prep and one-task-at-a-time guidance instead of pretending the user can brute-force through every slowdown."
  },
  {
    title: "Continuity Risk",
    description:
      "When infrastructure is shaky, the command center can still steer local work, continuity protocols, offline-friendly notes, and desktop coordination."
  }
];

const checklistRows = [
  {
    title: "Single Source Of Truth",
    description:
      "BlackHaven now centralizes instructions, links, file references, rationale, notes, and progress for a project instead of scattering them across chat history and browser tabs."
  },
  {
    title: "Step-Level Guidance",
    description:
      "Each checklist item can explain what the user needs to do next and why that step matters for the broader business, build, or travel outcome."
  },
  {
    title: "Next-Step Routing",
    description:
      "As the queue, workspace, or operator state changes, the checklist can light up the next human step instead of acting like a dead static todo list."
  }
];

const itineraryRows = [
  {
    title: "Activity Suggestions",
    description:
      "The app now generates personalized activity ideas that fit the user’s goals, energy, schedule, and current context instead of offering generic leisure filler."
  },
  {
    title: "Whole Itineraries",
    description:
      "BlackHaven can assemble day plans and travel-aware itineraries while protecting key productivity windows."
  },
  {
    title: "Wealth-First Travel Logic",
    description:
      "Travel planning respects health and output goals: preserve focus blocks, route around obvious friction, and support work, recovery, and movement as one system."
  }
];

const researchRows = [
  {
    title: "Research-Backed Discovery",
    description:
      "BlackHaven is growing beyond generic internet advice: the app suite already includes academic and evidence-oriented research flows that can feed execution, strategy, and operator learning."
  },
  {
    title: "World + Signal Monitoring",
    description:
      "The desktop apps include monitoring surfaces so the operator can track changing external conditions alongside memory, plans, and execution."
  },
  {
    title: "Human-Performance Framing",
    description:
      "The system is meant to improve the user’s conditions for clear thinking, recovery, and sustained output while staying grounded in actual operator needs."
  }
];

const supportRows = [
  {
    title: "Prepare The Human, Not Just The Task",
    description:
      "When the user needs a hard push, BlackHaven can suggest practical resets like a shower, comfortable clothing, clearing the desk, or focusing on one task only."
  },
  {
    title: "Supportive Recovery Prompts",
    description:
      "The product frames low-energy periods as routing problems, not character failures, and steers the user into the right mode for that moment."
  },
  {
    title: "Body-Doubling And Social Support",
    description:
      "BlackHaven can suggest supportive partner, family, or friend presence as part of the workflow while staying honest that richer automation here is still a roadmap item."
  }
];

const governanceRows = [
  {
    title: "AI Removes Drudgery, Not Ownership",
    description:
      "BlackHaven should free the operator from admin drag and repetitive coordination, but it does not replace taste, strategy, or human accountability."
  },
  {
    title: "Human Review For High-Stakes Decisions",
    description:
      "The right product behavior is escalation, not fake certainty: when something is sensitive or ambiguous, the system should route toward human judgment."
  },
  {
    title: "Operator-Controlled Reality",
    description:
      "Users should understand what BlackHaven automates, what it assists with, what is research-backed, and what still requires a founder or operator to decide."
  }
];

const liveNowRows = [
  "Adaptive survey and check-ins",
  "Manual-state-aware execution routing",
  "Supportive reset guidance and body-doubling suggestions",
  "Long-term memory and notes",
  "Prompt queue with durable execution",
  "Execution stream and proactive outputs",
  "Workspaces with shared context",
  "Interactive checklist hub with instructions, links, file references, notes, and progress state",
  "Local activity suggestions and itinerary generation",
  "Desktop-first local AI runtime preparation and model downloads",
  "Hardware-aware model/runtime tuning on desktop",
  "Encrypted local archive direction with companion-device continuity",
  "Remote desktop / remote control server",
  "AI guide and transparency surfaces",
  "Auth, access, and billing path",
  "Local AI setup and runtime management",
  "World monitor and operations dashboards",
  "Research-backed discovery and evidence-oriented execution framing"
];

const nextLayerRows = [
  "Biometric-driven reset routing and richer state machine behavior",
  "Automated body-doubling invites and deeper inner-circle coordination",
  "Interactive checklist steps with rich embedded files, live video previews, and progress automation",
  "Self-checking tasks that update from queue and project state",
  "External tool, calendar, and booking sync for itinerary intelligence",
  "Broader always-on scientific-advisor automation beyond the research surfaces already grounded in the apps"
];

const computePresetRows = [
  {
    title: "Eco",
    description:
      "Aggressive compaction, shorter responses, smaller local runtime footprint, and tighter cloud-cost guardrails. Best for daily operation, lighter hardware, and low-spend usage."
  },
  {
    title: "Balanced",
    description:
      "Moderate compaction, deeper reasoning, and standard guardrails. This is the default BlackHaven operating mode for most users and most machines."
  },
  {
    title: "Performance",
    description:
      "Maximum context retention, larger local runtime budget, and optional higher cloud spend when the user explicitly wants the best output quality."
  }
];

const economicsRows = [
  {
    title: "Cost-threshold AMM",
    description:
      "BlackHaven should compact when projected cloud input cost drifts above the chosen budget threshold, not only when an API context window is almost full."
  },
  {
    title: "Local resource AMM",
    description:
      "The same AMM logic should protect the user’s own machine by reacting to projected RAM, storage, and heavy-runtime pressure before the machine feels bad."
  },
  {
    title: "Semantic pinning",
    description:
      "Pinned specs, IDs, legal/accounting details, and decision-critical rationale stay intact. BlackHaven should cut fluff, not the facts that make execution safe."
  },
  {
    title: "User-controlled quality",
    description:
      "Users can choose more memory depth, longer answers, and more spend for higher quality when they want it. The app should make that tradeoff explicit instead of hiding it."
  }
];

const hardwareTierRows = [
  {
    title: "Minimum local tier",
    description:
      "Enough for lighter local AI, capture, queue continuity, and compact memory behavior. The app should auto-favor smaller models and stronger compaction here."
  },
  {
    title: "Recommended tier",
    description:
      "The sweet spot for most users: enough RAM, storage, and sustained performance for local memory authority, deeper retrieval, and stable day-to-day local AI."
  },
  {
    title: "High-performance node",
    description:
      "Best for heavier models, larger archives, overnight compaction, and more aggressive continuity-node use. This is where Performance mode should really shine."
  }
];

const infrastructureRows = [
  {
    title: "Why Local-First Matters",
    description:
      "Execution streams are only trustworthy when they can survive weak internet, protect private context, and keep running on infrastructure the user actually controls."
  },
  {
    title: "Why Power Strategy Matters",
    description:
      "Backup power, solar, batteries, and a serious home node are what keep the desktop command center dependable during real instability."
  },
  {
    title: "Why Remote Desktop Matters",
    description:
      "A phone becomes much more useful when it can reach a prepared desktop home base instead of trying to carry every heavy workflow itself."
  }
];

const readinessRows = [
  "Signed, trusted macOS and Windows installers",
  "A monitored support inbox and a public install guide",
  "Production auth, billing, and backend verification",
  "Documented local AI hardware, disk, power, and archive-storage expectations",
  "Remote pairing, LAN reachability, and degraded-internet testing",
  "Clear explanation of local-first value versus optional prepaid cloud add-ons",
  "Published AMM / compute preset behavior so users understand the quality-cost tradeoff",
  "Clear privacy, roadmap, recovery, and update expectations for end users",
  "Honest messaging about desktop-local compaction versus companion-device access"
];

export default function BlackHavenHomePage() {
  return (
    <div className={styles.page}>
      <section className={styles.hero}>
        <p className={styles.kicker}>BlackHaven Website</p>
        <h1>
          BlackHaven is the <span>execution-first AI command center</span> for life, business, and travel.
        </h1>
        <p>
          BlackHaven is built to feel like an active life partner, not a passive chat box. The desktop-led,
          local-first system already covers survey, memory, queue-backed work, remote desktop continuity, proactive
          execution, state-aware support guidance, an interactive checklist hub, local activity/itinerary generation,
          automatic model preparation, hardware-aware runtime tuning, and a desktop-side encrypted archive path for
          durable context. Optional prepaid cloud AI sits on top of that local core. The next product layer expands
          that foundation without pretending biometrics or rich external automation are already live.
        </p>
        <div className={styles.downloadMeta}>
          {heroSignals.map((signal) => (
            <span key={signal} className={styles.pill}>
              {signal}
            </span>
          ))}
        </div>
        <div className={styles.heroActions}>
          <Link href="/blackhaven/downloads" className={styles.primary}>
            Desktop Downloads
          </Link>
          <Link href="#how-it-works" className={styles.secondary}>
            How It Works
          </Link>
          <Link href="/blackhaven/readiness" className={styles.secondary}>
            Launch Readiness
          </Link>
        </div>
      </section>

      <section id="how-it-works" className={styles.section}>
        <h2>How The System Works In Practice</h2>
        <p className={styles.sectionIntro}>
          The website sells the operating loop the apps already support instead of flattening the product into
          “just chat with local AI.”
        </p>
        <div className={styles.grid}>
          {appLoopRows.map((row) => (
            <article key={row.title} className={styles.card}>
              <h3>{row.title}</h3>
              <p>{row.description}</p>
            </article>
          ))}
        </div>
      </section>

      <section id="app-suite" className={styles.section}>
        <h2>How The App Suite Actually Splits Up</h2>
        <p className={styles.sectionIntro}>
          BlackHaven now sells the real product shape: macOS and Windows are the local-memory command centers, and
          mobile stays the companion layer for capture, control, and continuity.
        </p>
        <div className={styles.grid}>
          {appSurfaceRows.map((row) => (
            <article key={row.title} className={styles.card}>
              <h3>{row.title}</h3>
              <p>{row.description}</p>
            </article>
          ))}
        </div>
        <div className={styles.grid}>
          {productSplitRows.map((row) => (
            <article key={row.title} className={styles.card}>
              <h3>{row.title}</h3>
              <p>{row.description}</p>
            </article>
          ))}
        </div>
      </section>

      <section id="state-aware" className={styles.section}>
        <h2>State-Aware Execution</h2>
        <p className={styles.sectionIntro}>
          BlackHaven should route work based on the user’s actual situation, not force the same interaction every
          time.
        </p>
        <div className={styles.grid}>
          {stateRows.map((row) => (
            <article key={row.title} className={styles.card}>
              <h3>{row.title}</h3>
              <p>{row.description}</p>
            </article>
          ))}
        </div>
      </section>

      <section id="checklists" className={styles.section}>
        <h2>The Interactive Checklist Hub</h2>
        <p className={styles.sectionIntro}>
          BlackHaven should evolve from flat tasks toward a central operating surface that keeps instructions,
          resources, and progress in one place.
        </p>
        <div className={styles.grid}>
          {checklistRows.map((row) => (
            <article key={row.title} className={styles.card}>
              <h3>{row.title}</h3>
              <p>{row.description}</p>
            </article>
          ))}
        </div>
      </section>

      <section id="travel-intelligence" className={styles.section}>
        <h2>Travel And Activity Intelligence</h2>
        <p className={styles.sectionIntro}>
          The same command-center core can support life and travel planning, not only work execution.
        </p>
        <div className={styles.grid}>
          {itineraryRows.map((row) => (
            <article key={row.title} className={styles.card}>
              <h3>{row.title}</h3>
              <p>{row.description}</p>
            </article>
          ))}
        </div>
      </section>

      <section id="research" className={styles.section}>
        <h2>Research And Monitoring</h2>
        <p className={styles.sectionIntro}>
          BlackHaven should not feel like a sealed chat box. The apps already point toward research-backed discovery,
          evidence-aware execution, and operator-grade monitoring in the same desktop-led system.
        </p>
        <div className={styles.grid}>
          {researchRows.map((row) => (
            <article key={row.title} className={styles.card}>
              <h3>{row.title}</h3>
              <p>{row.description}</p>
            </article>
          ))}
        </div>
      </section>

      <section id="healthy-wealthy" className={styles.section}>
        <h2>Healthy + Wealthy Support</h2>
        <p className={styles.sectionIntro}>
          BlackHaven should support better execution conditions in a practical, non-medical way: reset the person,
          reduce friction, and make the next step easier to take.
        </p>
        <div className={styles.grid}>
          {supportRows.map((row) => (
            <article key={row.title} className={styles.card}>
              <h3>{row.title}</h3>
              <p>{row.description}</p>
            </article>
          ))}
        </div>
      </section>

      <section id="governance" className={styles.section}>
        <h2>Human Governance Still Matters</h2>
        <p className={styles.sectionIntro}>
          The goal is to make the operator stronger, not obsolete. BlackHaven should sell that clearly because it is
          part of why the product is trustworthy.
        </p>
        <div className={styles.grid}>
          {governanceRows.map((row) => (
            <article key={row.title} className={styles.card}>
              <h3>{row.title}</h3>
              <p>{row.description}</p>
            </article>
          ))}
        </div>
      </section>

      <section id="live-now" className={styles.section}>
        <h2>Live Now Vs Next Layer</h2>
        <p className={styles.sectionIntro}>
          The website should sell hard and stay honest. These are the parts already grounded in the apps versus the
          product layer still being built on top.
        </p>
        <div className={styles.grid}>
          <article className={`${styles.card} ${styles.featurePanel}`}>
            <div>
              <p className={styles.panelLabel}>Live now</p>
              <h3>Real product surface already visible in the apps</h3>
            </div>
            <ul className={styles.checklist}>
              {liveNowRows.map((row) => (
                <li key={row}>{row}</li>
              ))}
            </ul>
          </article>
          <article className={`${styles.card} ${styles.featurePanel}`}>
            <div>
              <p className={styles.panelLabel}>Next layer</p>
              <h3>Roadmap features this website can frame without falsely claiming they are fully live</h3>
            </div>
            <ul className={styles.checklist}>
              {nextLayerRows.map((row) => (
                <li key={row}>{row}</li>
              ))}
            </ul>
          </article>
        </div>
      </section>

      <section id="compute-economics" className={styles.section}>
        <h2>Compute Economics And Active Memory Management</h2>
        <p className={styles.sectionIntro}>
          BlackHaven should act like a financially responsible operator on the user&apos;s behalf. It should protect
          quality, but it should also protect API spend and local hardware load before either one gets ugly.
        </p>
        <div className={styles.grid}>
          {economicsRows.map((row) => (
            <article key={row.title} className={styles.card}>
              <h3>{row.title}</h3>
              <p>{row.description}</p>
            </article>
          ))}
        </div>
        <article className={`${styles.card} ${styles.featurePanel}`}>
          <div>
            <p className={styles.panelLabel}>User-facing presets</p>
            <h3>Preset-first controls keep the product legible while still allowing advanced users to tune the envelope.</h3>
          </div>
          <ul className={styles.checklist}>
            {computePresetRows.map((row) => (
              <li key={row.title}>
                <strong>{row.title}:</strong> {row.description}
              </li>
            ))}
          </ul>
        </article>
      </section>

      <section id="hardware-budgeting" className={styles.section}>
        <h2>Hardware Budgeting For Local AI</h2>
        <p className={styles.sectionIntro}>
          BlackHaven is not just choosing models. It is choosing what class of experience the user&apos;s computer can
          support without overheating, stalling, or quietly turning local AI into a bad purchase.
        </p>
        <div className={styles.grid}>
          {hardwareTierRows.map((row) => (
            <article key={row.title} className={styles.card}>
              <h3>{row.title}</h3>
              <p>{row.description}</p>
            </article>
          ))}
        </div>
        <article className={`${styles.card} ${styles.featurePanel}`}>
          <div>
            <p className={styles.panelLabel}>What the app should communicate</p>
            <h3>Users should know what their machine can handle and what BlackHaven is doing to stay inside that envelope.</h3>
          </div>
          <ul className={styles.checklist}>
            <li>Which hardware tier the current machine falls into.</li>
            <li>When BlackHaven is compacting more aggressively to protect RAM, storage, or thermal headroom.</li>
            <li>When the app is automatically choosing a smaller local model or a lighter context budget.</li>
            <li>When a heavier local node or optional cloud add-on would improve quality beyond the current machine.</li>
          </ul>
        </article>
      </section>

      <section id="desktop" className={styles.section}>
        <h2>Desktop-Led, With Real Companion Apps</h2>
        <p className={styles.sectionIntro}>
          The desktop app is the main BlackHaven experience. Mobile continues the loop away from the desk.
        </p>
        <article className={`${styles.card} ${styles.downloadCard}`}>
          <div className={styles.downloadMeta}>
            <span className={styles.pill}>macOS</span>
            <span className={styles.pill}>Windows</span>
            <span className={styles.pill}>Desktop home base</span>
            <span className={styles.pill}>Companion mobile flow</span>
            <span className={styles.pill}>Encrypted archive</span>
            <span className={styles.pill}>Auto-tuned context</span>
          </div>
          <p>
            The cleanest model is simple: install BlackHaven on the main machine first, then use mobile as a
            companion layer for capture, check-ins, memory continuity, and remote control. The paired desktop is the
            full local-memory authority that manages archive, compaction, and heavier local AI work.
          </p>
          <Link href="/blackhaven/downloads" className={styles.primary}>
            Open Downloads Hub
          </Link>
        </article>
      </section>

      <section id="infrastructure" className={styles.section}>
        <h2>Why The Infrastructure Story Still Matters</h2>
        <p className={styles.sectionIntro}>
          Local-first AI, remote desktop reachability, and resilient power are not side notes. They are what make the
          execution story believable in the real world.
        </p>
        <div className={styles.grid}>
          {infrastructureRows.map((row) => (
            <article key={row.title} className={styles.card}>
              <h3>{row.title}</h3>
              <p>{row.description}</p>
            </article>
          ))}
        </div>
      </section>

      <section id="readiness" className={styles.section}>
        <h2>Real-World Readiness</h2>
        <p className={styles.sectionIntro}>
          Broad release still depends on trust, install quality, support coverage, and clear honesty about what is
          live versus roadmap.
        </p>
        <article className={`${styles.card} ${styles.featurePanel}`}>
          <div>
            <p className={styles.panelLabel}>What still has to be true</p>
            <h3>Strong positioning only works if launch, support, and product truth all line up.</h3>
          </div>
          <ul className={styles.checklist}>
            {readinessRows.map((row) => (
              <li key={row}>{row}</li>
            ))}
          </ul>
        </article>
        <div className={styles.heroActions}>
          <Link href="/blackhaven/readiness" className={styles.secondary}>
            Open Full Checklist
          </Link>
        </div>
      </section>

      <section className={styles.banner}>
        BlackHaven is the execution software and command-center layer. The website now sells the real product shape:
        a desktop-first, local-memory life/business/travel system with strong local AI, encrypted archive, companion
        mobile continuity, honest cloud economics, and an AMM layer that protects both user cost and user hardware.
      </section>
    </div>
  );
}
