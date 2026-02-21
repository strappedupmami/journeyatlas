(function () {
  const toolKey = document.body.getAttribute("data-tool") || "chat";

  const tools = {
    chat: {
      route: "tool-chat.html",
      title: "Text Chat Workspace",
      kicker: "AI Concierge Tool",
      subtitle:
        "High-clarity dialogue workspace for planning, debugging, and executive-level decisions.",
      launch: "chat",
      summary: [
        "Fast prompt-response loop with clean context framing.",
        "Designed for daily operational decisions and rapid iteration.",
        "Routes to the chat feature immediately, not to generic tabs.",
      ],
      layout: `
        <section class="card tool-section">
          <h3>Conversation setup</h3>
          <p>Define the context once, then run a focused conversation thread.</p>
          <div class="tool-field"><label>Current objective</label><input placeholder="Example: ship auth fix + verify production health" /></div>
          <div class="tool-field"><label>Constraints</label><textarea placeholder="Budget, time window, legal/safety limits, dependencies"></textarea></div>
          <div class="tool-note">Use this when you need clear decisions fast.</div>
        </section>
        <section class="card tool-section">
          <h3>Output style</h3>
          <p>Set the response style you want before entering chat mode.</p>
          <div class="tool-field"><label>Depth</label><select><option>Quick</option><option selected>Balanced</option><option>Deep</option></select></div>
          <div class="tool-field"><label>Tone</label><select><option selected>Executive</option><option>Pragmatic</option><option>Supportive</option></select></div>
          <ul class="tool-list"><li>Decision-ready summaries</li><li>Clear next action now</li><li>Risk-first framing</li></ul>
        </section>`,
    },
    trip: {
      route: "tool-trip.html",
      title: "Trip Planning Workspace",
      kicker: "AI Mobility Tool",
      subtitle:
        "Dedicated planning surface for legal routes, safe-harbor backups, and execution-first travel.",
      launch: "trip",
      summary: [
        "Plan travel around real constraints, not generic tourism.",
        "Supports heavy-mileage road workflows and business mobility.",
        "Direct launch into trip-planning mode.",
      ],
      layout: `
        <section class="card tool-section">
          <h3>Route profile</h3>
          <p>Capture mission details before generating the plan.</p>
          <div class="tool-field"><label>Region</label><input placeholder="Example: North + coast" /></div>
          <div class="tool-field"><label>Trip window (days)</label><input placeholder="Example: 3" /></div>
          <div class="tool-field"><label>People count</label><input placeholder="Example: 2" /></div>
        </section>
        <section class="card tool-section">
          <h3>Operational constraints</h3>
          <p>Bias planning toward resilience and legality.</p>
          <ul class="tool-list"><li>Legal overnight points only</li><li>Service/refill/maintenance stops</li><li>Safe-harbor fallback mapping</li></ul>
          <div class="tool-field"><label>Primary concern</label><textarea placeholder="Example: no service areas, late arrivals, safety risk"></textarea></div>
        </section>`,
    },
    voice: {
      route: "tool-voice.html",
      title: "Voice Check-In Workspace",
      kicker: "AI Voice Tool",
      subtitle:
        "Hands-light voice intake for quick operational updates while moving.",
      launch: "voice",
      summary: [
        "Built for live check-ins during intense days.",
        "Converts spoken status into clear execution actions.",
        "Direct voice-mode launch path.",
      ],
      layout: `
        <section class="card tool-section">
          <h3>Voice intake structure</h3>
          <p>Use this script to keep check-ins concise and useful.</p>
          <ul class="tool-list"><li>What changed since last check-in?</li><li>What is blocked right now?</li><li>What is the next action in 30 minutes?</li></ul>
          <div class="tool-field"><label>Check-in note</label><textarea placeholder="Quick summary for transcription context"></textarea></div>
        </section>
        <section class="card tool-section">
          <h3>Execution handoff</h3>
          <p>After voice capture, push one concrete move.</p>
          <div class="tool-field"><label>Priority tag</label><select><option selected>Critical</option><option>High</option><option>Normal</option></select></div>
          <div class="tool-field"><label>Immediate action</label><input placeholder="Example: lock 25-minute focus sprint" /></div>
        </section>`,
    },
    survey: {
      route: "tool-survey.html",
      title: "Adaptive Deep Survey Workspace",
      kicker: "AI Personalization Tool",
      subtitle:
        "A long-form branching onboarding flow that builds strong personalization baselines.",
      launch: "survey",
      summary: [
        "Designed for 20-30 minutes of profile depth.",
        "Required before high-quality mission briefing unlock.",
        "Routes directly to deep-survey mode.",
      ],
      layout: `
        <section class="card tool-section">
          <h3>Survey protocol</h3>
          <p>Run in one uninterrupted session for best quality.</p>
          <ul class="tool-list"><li>Daily execution behavior</li><li>Mid-term project strategy</li><li>Long-horizon mission + wealth targets</li><li>Stress and recovery patterns</li></ul>
        </section>
        <section class="card tool-section">
          <h3>Completion criteria</h3>
          <p>The system unlocks stronger proactive outputs only after full completion.</p>
          <div class="tool-field"><label>Session commitment</label><select><option selected>25 minutes</option><option>30+ minutes</option></select></div>
          <div class="tool-field"><label>Notes before starting</label><textarea placeholder="Anything the system should prioritize while branching questions"></textarea></div>
        </section>`,
    },
    notes: {
      route: "tool-notes.html",
      title: "Notes Capture Workspace",
      kicker: "AI Memory Tool",
      subtitle:
        "Structured capture for high-signal notes that improve long-term personalization.",
      launch: "notes",
      summary: [
        "Capture tactical notes and strategic intent cleanly.",
        "Designed for retrieval-friendly memory over months and years.",
        "Direct routing to notes mode.",
      ],
      layout: `
        <section class="card tool-section">
          <h3>High-signal note format</h3>
          <p>Use one note per meaningful objective.</p>
          <div class="tool-field"><label>Title</label><input placeholder="Example: Q2 revenue sprint" /></div>
          <div class="tool-field"><label>Daily / Mid / Long structure</label><textarea placeholder="Daily: ...\nMid-term: ...\nLong-term: ..."></textarea></div>
        </section>
        <section class="card tool-section">
          <h3>Retention quality</h3>
          <p>Write notes that are actionable, not vague.</p>
          <ul class="tool-list"><li>One measurable target</li><li>One constraint</li><li>One next action</li><li>One deadline or checkpoint</li></ul>
          <div class="tool-note">Better note quality = better memory retrieval quality.</div>
        </section>`,
    },
    memory: {
      route: "tool-memory.html",
      title: "Memory Import Workspace",
      kicker: "AI Context Tool",
      subtitle:
        "Import structured memories from external sources into Atlas/אטלס context layers.",
      launch: "memory",
      summary: [
        "Brings Notebook/Thread insights into your operational context.",
        "Supports long-term preference and pattern continuity.",
        "Direct routing to memory import mode.",
      ],
      layout: `
        <section class="card tool-section">
          <h3>Import format</h3>
          <p>Use structured JSON to preserve retrieval quality.</p>
          <div class="tool-field"><label>Payload sketch</label><textarea placeholder='{"items":[{"title":"...","content":"...","tags":["..."],"source":"notebook"}]}'></textarea></div>
        </section>
        <section class="card tool-section">
          <h3>Safety checks</h3>
          <p>Only import data you are allowed to store and process.</p>
          <ul class="tool-list"><li>No secrets/tokens</li><li>No third-party private data without consent</li><li>Prefer distilled, structured records</li></ul>
        </section>`,
    },
    briefing: {
      route: "tool-briefing.html",
      title: "Mission Briefing Workspace",
      kicker: "AI Proactive Tool",
      subtitle:
        "Execution-first briefing stream for daily, mid-term, and long-horizon priorities.",
      launch: "feed",
      summary: [
        "Replaces generic feed with mission-briefing framing.",
        "Shows next-action-now with strategic awareness.",
        "Best results after deep survey completion.",
      ],
      layout: `
        <section class="card tool-section">
          <h3>Briefing inputs</h3>
          <p>Define pressure and objectives before refresh.</p>
          <div class="tool-field"><label>Today's focus</label><input placeholder="Example: close auth hardening + ship release" /></div>
          <div class="tool-field"><label>Current blocker</label><input placeholder="Example: context switching + deployment uncertainty" /></div>
          <div class="tool-field"><label>Energy level</label><select><option>1</option><option>2</option><option selected>3</option><option>4</option><option>5</option></select></div>
        </section>
        <section class="card tool-section">
          <h3>Output controls</h3>
          <p>Tune how proactive outputs are generated.</p>
          <ul class="tool-list"><li>Cadence: steady / aggressive</li><li>Detail: concise / standard / expanded</li><li>Company-awareness: on/off</li><li>Reminder suggestions: on/off</li></ul>
        </section>`,
    },
  };

  const def = tools[toolKey] || tools.chat;

  function normalizeApiBase(value) {
    return String(value || "").trim().replace(/\/+$/, "");
  }

  function sanitizeApiBase(value) {
    const normalized = normalizeApiBase(value);
    if (!normalized) return "https://api.atlasmasa.com";
    try {
      const url = new URL(normalized);
      const host = (url.hostname || "").toLowerCase();
      if (!/^https?:$/.test(url.protocol)) return "https://api.atlasmasa.com";
      if (
        host === "atlasmasa.com" ||
        host === "www.atlasmasa.com" ||
        host === window.location.hostname.toLowerCase()
      ) {
        return "https://api.atlasmasa.com";
      }
      return normalizeApiBase(url.toString());
    } catch (_error) {
      return "https://api.atlasmasa.com";
    }
  }

  function getApiBase() {
    const params = new URLSearchParams(window.location.search);
    const fromQuery = params.get("api_base");
    if (fromQuery) {
      const normalized = sanitizeApiBase(fromQuery);
      window.localStorage.setItem("atlas_api_base", normalized);
      return normalized;
    }
    const fromStorage = window.localStorage.getItem("atlas_api_base");
    const normalized = sanitizeApiBase(fromStorage || "https://api.atlasmasa.com");
    window.localStorage.setItem("atlas_api_base", normalized);
    return normalized;
  }

  const apiBase = getApiBase();
  const workspaceHref = `${def.route}?api_base=${encodeURIComponent(apiBase)}`;

  const titleEl = document.getElementById("tool-title");
  const subtitleEl = document.getElementById("tool-subtitle");
  const kickerEl = document.getElementById("tool-kicker");
  const summaryEl = document.getElementById("tool-summary");
  const layoutEl = document.getElementById("tool-layout");
  const openBtn = document.getElementById("open-tool-btn");
  const fullBtn = document.getElementById("open-studio-btn");

  document.title = `Atlas/אטלס | ${def.title}`;
  if (titleEl) titleEl.textContent = def.title;
  if (subtitleEl) subtitleEl.textContent = def.subtitle;
  if (kickerEl) kickerEl.textContent = def.kicker;
  if (summaryEl) {
    summaryEl.innerHTML = def.summary.map((line) => `<li>${line}</li>`).join("");
  }
  if (layoutEl) {
    layoutEl.innerHTML = def.layout;
  }
  if (openBtn) {
    openBtn.href = workspaceHref;
    openBtn.textContent = `Use ${def.title}`;
  }
  if (fullBtn) {
    fullBtn.href = `concierge-local.html?launch=${encodeURIComponent(def.launch)}&api_base=${encodeURIComponent(apiBase)}`;
  }

  document.querySelectorAll(".tool-link").forEach((link) => {
    const href = (link.getAttribute("href") || "").split("?")[0];
    if (href) {
      link.setAttribute("href", `${href}?api_base=${encodeURIComponent(apiBase)}`);
    }
    if (link.getAttribute("data-tool") === toolKey) {
      link.setAttribute("aria-current", "page");
    }
  });
})();
