(function () {
  const config = window.ATLAS_APPLE_WEB_CONFIG || {};
  const apiStatus = document.getElementById("apple-api-status");
  const readinessList = document.getElementById("apple-readiness-list");

  function normalizeApiBase(value) {
    return String(value || "").trim().replace(/\/+$/, "");
  }

  function getApiBase() {
    const query = new URLSearchParams(window.location.search).get("api_base");
    const stored = window.localStorage.getItem("atlas_api_base");
    return normalizeApiBase(query || stored || "https://api.atlasmasa.com");
  }

  function setFeatureState(id, tone, title, detail) {
    const card = document.querySelector('[data-feature="' + id + '"]');
    if (!card) return;
    card.setAttribute("data-tone", tone);
    const badge = card.querySelector("[data-role='badge']");
    const text = card.querySelector("[data-role='detail']");
    if (badge) badge.textContent = title;
    if (text) text.textContent = detail;
  }

  function addReadinessItem(label) {
    if (!readinessList || !label) return;
    const item = document.createElement("li");
    item.textContent = label;
    readinessList.appendChild(item);
  }

  function clearReadiness() {
    if (readinessList) readinessList.innerHTML = "";
  }

  async function fetchHealth() {
    try {
      const response = await fetch(getApiBase() + "/health", {
        headers: { Accept: "application/json" },
        credentials: "omit",
      });
      if (!response.ok) throw new Error("health_unavailable");
      return await response.json();
    } catch (_error) {
      return null;
    }
  }

  function browserSupportsWebPush() {
    return "serviceWorker" in navigator && "PushManager" in window && "Notification" in window;
  }

  async function setupPushCard() {
    if (!browserSupportsWebPush()) {
      setFeatureState("push", "warn", "Browser support missing", "Safari/iOS web push requires Notifications, Push API, and Service Worker support.");
      return;
    }
    if (!config.pushPublicKey || !config.pushSubscribeEndpoint) {
      setFeatureState("push", "wait", "Scaffolded", "Service worker support is in place. Add your VAPID public key and subscribe endpoint to make push live.");
      addReadinessItem("Set `pushPublicKey` and `pushSubscribeEndpoint` in `website/apple-web-config.js`.");
      return;
    }
    try {
      await navigator.serviceWorker.register("/apple-web-sw.js");
      setFeatureState("push", "ok", "Ready to enroll", "Safari/iOS web push can now register clients once your backend subscribe route is active.");
    } catch (_error) {
      setFeatureState("push", "warn", "Registration failed", "The service worker could not be registered in this environment.");
    }
  }

  function setupStaticFeatureCards(health) {
    if (health && health.capabilities && health.capabilities.apple_oauth) {
      setFeatureState("siwa", "ok", "Live", "Sign in with Apple is already wired through the auth portal and backend OAuth exchange.");
    } else {
      setFeatureState("siwa", "wait", "Portal-ready", "The website buttons exist, but the backend still needs live Apple OAuth portal credentials.");
      addReadinessItem("Create or confirm a Sign in with Apple Services ID and web redirect in Apple Developer.");
    }

    if (health && health.capabilities && health.capabilities.billing) {
      setFeatureState("apple-pay", "ok", "Backend ready", "Stripe checkout is configured server-side. Apple Pay becomes live after Stripe domain verification in Safari.");
    } else {
      setFeatureState("apple-pay", "wait", "Backend pending", "Website pricing copy is in place, but billing must be configured before Apple Pay can actually process checkout.");
      addReadinessItem("Set Stripe billing env vars and verify the domain for Apple Pay in Stripe.");
    }

    if (config.mapkitToken) {
      setFeatureState("mapkit", "ok", "Token configured", "MapKit JS can be loaded as soon as you attach your signed token and map use-case UI.");
    } else {
      setFeatureState("mapkit", "wait", "Config pending", "MapKit JS scaffolding is ready for a signed token, but no token is configured yet.");
      addReadinessItem("Create a MapKit JS key and paste the token into `mapkitToken`.");
    }

    if (config.weatherkitEndpoint) {
      setFeatureState("weatherkit", "ok", "Endpoint configured", "The site can call a server-owned WeatherKit endpoint once it is deployed.");
    } else {
      setFeatureState("weatherkit", "wait", "Server endpoint pending", "WeatherKit should stay server-mediated. Add a signed endpoint before exposing forecasts publicly.");
      addReadinessItem("Create a WeatherKit key and a signed backend endpoint, then set `weatherkitEndpoint`.");
    }

    if (config.cloudKitContainerId) {
      setFeatureState("cloudkit", "ok", "Container configured", "CloudKit JS can be mounted for user-owned iCloud data flows.");
    } else {
      setFeatureState("cloudkit", "wait", "Container pending", "CloudKit JS is best added only after a container name and record schema are finalized.");
      addReadinessItem("Choose a CloudKit container ID and record model, then set `cloudKitContainerId`.");
    }

    if (config.musicKitDeveloperToken) {
      setFeatureState("musickit", "ok", "Developer token configured", "MusicKit JS can be activated for previews or subscriber playback.");
    } else {
      setFeatureState("musickit", "wait", "Token pending", "MusicKit needs a developer token before the web player can be enabled.");
      addReadinessItem("Create a MusicKit key/token and set `musicKitDeveloperToken`.");
    }

    if (config.walletPassBaseUrl) {
      setFeatureState("wallet", "ok", "Pass endpoint configured", "Wallet pass download/update flows can now be attached to tickets, bookings, or loyalty cards.");
    } else {
      setFeatureState("wallet", "wait", "Pass endpoint pending", "Wallet is ready for backend integration once a Pass Type ID certificate and `.pkpass` generator exist.");
      addReadinessItem("Create a Pass Type ID and signing certificate, then set `walletPassBaseUrl` to your pass endpoint.");
    }
  }

  async function init() {
    clearReadiness();
    const health = await fetchHealth();
    if (apiStatus) {
      apiStatus.textContent = health
        ? "Backend health reached. Apple OAuth and billing status were checked live."
        : "Backend health was not reachable from this page, so readiness below includes safe fallbacks.";
    }
    setupStaticFeatureCards(health);
    await setupPushCard();
    if (readinessList && !readinessList.children.length) {
      addReadinessItem("No Apple portal work is blocking the currently-implemented website features.");
    }
  }

  init();
})();
