(function () {
  const titleEl = document.getElementById("auth-title");
  const subtitleEl = document.getElementById("auth-subtitle");
  const appleBtn = document.getElementById("apple-btn");
  const googleBtn = document.getElementById("google-btn");
  const passkeySigninBtn = document.getElementById("passkey-signin-btn");
  const passkeySignupBtn = document.getElementById("passkey-signup-btn");
  const statusEl = document.getElementById("auth-status");
  const surveyLink = document.getElementById("survey-link");
  const studioLink = document.getElementById("studio-link");

  const mode = (document.body.getAttribute("data-auth-mode") || "signup").toLowerCase();
  const params = new URLSearchParams(window.location.search);
  const authResult = params.get("auth");
  const authReason = params.get("reason");
  const stayOnAuthPage = params.get("stay_auth") === "1";

  if (mode === "signin") {
    document.title = "Atlas Masa | Sign In";
    if (titleEl) titleEl.textContent = "Welcome back";
    if (subtitleEl) {
      subtitleEl.textContent =
        "Classic, secure account access. Use Apple, Google, or Passwordless (more secure) sign in.";
    }
  } else {
    if (titleEl) titleEl.textContent = "Create your account";
    if (subtitleEl) {
      subtitleEl.textContent =
        "Classic, secure account creation. Use Apple, Google, or Passwordless (more secure) sign up.";
    }
  }

  function setStatus(message, tone) {
    if (!statusEl) return;
    if (!message) {
      statusEl.style.display = "none";
      statusEl.removeAttribute("data-tone");
      statusEl.textContent = "";
      return;
    }
    statusEl.style.display = "block";
    statusEl.setAttribute("data-tone", tone || "warn");
    statusEl.textContent = message;
  }

  function normalizeApiBase(value) {
    return String(value || "").trim().replace(/\/+$/, "");
  }

  function getApiBase() {
    const fromQuery = params.get("api_base");
    if (fromQuery) {
      const normalized = normalizeApiBase(fromQuery);
      window.localStorage.setItem("atlas_api_base", normalized);
      return normalized;
    }
    const fromStorage = window.localStorage.getItem("atlas_api_base");
    return normalizeApiBase(fromStorage || "https://api.atlasmasa.com");
  }

  const API_BASE = getApiBase();

  function buildPostAuthDestination() {
    const destination = mode === "signin" ? "tool-chat.html" : "tool-survey.html";
    return destination + "?api_base=" + encodeURIComponent(API_BASE);
  }

  if (surveyLink) {
    surveyLink.href = "tool-survey.html?api_base=" + encodeURIComponent(API_BASE);
  }
  if (studioLink) {
    studioLink.href = "tool-chat.html?api_base=" + encodeURIComponent(API_BASE);
  }

  function toBase64Url(data) {
    if (!data) return "";
    const bytes = new Uint8Array(data);
    let binary = "";
    for (let i = 0; i < bytes.length; i += 1) {
      binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
  }

  function fromBase64Url(value) {
    const input = String(value || "").replace(/-/g, "+").replace(/_/g, "/");
    const padLength = input.length % 4 === 0 ? 0 : 4 - (input.length % 4);
    const padded = input + "=".repeat(padLength);
    const binary = atob(padded);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes.buffer;
  }

  function normalizeCredentialDescriptor(credential) {
    if (!credential || typeof credential !== "object") return credential;
    const normalized = Object.assign({}, credential);
    if (typeof normalized.id === "string") {
      normalized.id = fromBase64Url(normalized.id);
    }
    return normalized;
  }

  function pickPublicKeyOptions(options) {
    if (!options || typeof options !== "object") return {};
    if (options.publicKey && typeof options.publicKey === "object") return options.publicKey;
    if (options.public_key && typeof options.public_key === "object") return options.public_key;
    return options;
  }

  function toArrayOrFallback(value, fallback) {
    return Array.isArray(value) ? value : fallback;
  }

  function decodeBase64IfString(value) {
    return typeof value === "string" ? fromBase64Url(value) : value;
  }

  function prepareRegistrationOptions(options) {
    const raw = Object.assign({}, pickPublicKeyOptions(options));
    const normalized = Object.assign({}, raw);

    normalized.challenge = decodeBase64IfString(raw.challenge);
    normalized.pubKeyCredParams = toArrayOrFallback(
      raw.pubKeyCredParams || raw.pub_key_cred_params,
      [
        { type: "public-key", alg: -7 },
        { type: "public-key", alg: -257 },
      ]
    );

    const user = raw.user || {};
    if (user && typeof user === "object") {
      normalized.user = Object.assign({}, user, {
        id: decodeBase64IfString(user.id),
      });
    }

    if (!Array.isArray(normalized.excludeCredentials) && Array.isArray(raw.exclude_credentials)) {
      normalized.excludeCredentials = raw.exclude_credentials;
    }
    if (!normalized.authenticatorSelection && raw.authenticator_selection) {
      normalized.authenticatorSelection = raw.authenticator_selection;
    }
    if (!normalized.attestation && raw.attestation_conveyance_preference) {
      normalized.attestation = raw.attestation_conveyance_preference;
    }

    if (Array.isArray(normalized.excludeCredentials)) {
      normalized.excludeCredentials = normalized.excludeCredentials.map(
        normalizeCredentialDescriptor
      );
    }
    return normalized;
  }

  function prepareAuthenticationOptions(options) {
    const raw = Object.assign({}, pickPublicKeyOptions(options));
    const normalized = Object.assign({}, raw);

    normalized.challenge = decodeBase64IfString(raw.challenge);
    if (!Array.isArray(normalized.allowCredentials) && Array.isArray(raw.allow_credentials)) {
      normalized.allowCredentials = raw.allow_credentials;
    }
    if (!normalized.rpId && raw.rp_id) {
      normalized.rpId = raw.rp_id;
    }
    if (!normalized.userVerification && raw.user_verification) {
      normalized.userVerification = raw.user_verification;
    }

    if (Array.isArray(normalized.allowCredentials)) {
      normalized.allowCredentials = normalized.allowCredentials.map(
        normalizeCredentialDescriptor
      );
    }
    return normalized;
  }

  function serializeRegistrationCredential(credential) {
    return {
      id: credential.id,
      rawId: toBase64Url(credential.rawId),
      type: credential.type,
      response: {
        clientDataJSON: toBase64Url(credential.response.clientDataJSON),
        attestationObject: toBase64Url(credential.response.attestationObject),
        transports:
          typeof credential.response.getTransports === "function"
            ? credential.response.getTransports()
            : [],
      },
      clientExtensionResults: credential.getClientExtensionResults(),
    };
  }

  function serializeAuthenticationCredential(credential) {
    return {
      id: credential.id,
      rawId: toBase64Url(credential.rawId),
      type: credential.type,
      response: {
        clientDataJSON: toBase64Url(credential.response.clientDataJSON),
        authenticatorData: toBase64Url(credential.response.authenticatorData),
        signature: toBase64Url(credential.response.signature),
        userHandle: credential.response.userHandle
          ? toBase64Url(credential.response.userHandle)
          : null,
      },
      clientExtensionResults: credential.getClientExtensionResults(),
    };
  }

  async function fetchJson(path, method, body, includeApiKey) {
    const url = API_BASE + path;
    const headers = { "Content-Type": "application/json" };
    if (includeApiKey) {
      const key = window.localStorage.getItem("atlas_api_key") || "";
      if (key) headers["x-api-key"] = key;
    }

    try {
      const response = await fetch(url, {
        method: method || "GET",
        headers,
        credentials: "include",
        body: body === undefined ? undefined : JSON.stringify(body),
      });
      const text = await response.text();
      let payload = {};
      try {
        payload = text ? JSON.parse(text) : {};
      } catch (_error) {
        payload = { raw: text };
      }
      return { ok: response.ok, status: response.status, payload };
    } catch (_error) {
      return { ok: false, status: 0, payload: {} };
    }
  }

  function setButtonsLoading(loading) {
    [appleBtn, googleBtn, passkeySigninBtn, passkeySignupBtn].forEach(function (btn) {
      if (!btn) return;
      btn.disabled = loading;
    });
  }

  async function startOAuth(provider) {
    setButtonsLoading(true);
    setStatus("Redirecting to secure sign-in...", "warn");
    const returnTo =
      (mode === "signin" ? "/signin.html" : "/signup.html") +
      "?api_base=" +
      encodeURIComponent(API_BASE);

    const result = await fetchJson(
      "/v1/auth/" + provider + "/start?return_to=" + encodeURIComponent(returnTo),
      "GET",
      undefined,
      false
    );

    if (!result.ok || !result.payload.authorize_url) {
      setButtonsLoading(false);
      setStatus("Sign-in service is temporarily unavailable. Please try again.", "warn");
      return;
    }

    window.location.href = result.payload.authorize_url;
  }

  async function signInWithPasskey() {
    if (!window.PublicKeyCredential) {
      setStatus("This browser does not support passkeys.", "warn");
      return;
    }

    setButtonsLoading(true);
    setStatus("Starting passwordless sign-in...", "warn");

    const start = await fetchJson(
      "/v1/auth/passkey/login/start",
      "POST",
      {},
      false
    );

    if (!start.ok || !start.payload.options || !start.payload.request_id) {
      setButtonsLoading(false);
      setStatus(
        "Passwordless (more secure) sign in could not start right now.",
        "warn"
      );
      return;
    }

    let credential;
    try {
      const publicKey = prepareAuthenticationOptions(start.payload.options);
      credential = await navigator.credentials.get({ publicKey: publicKey });
    } catch (error) {
      setButtonsLoading(false);
      setStatus("Passkey sign-in cancelled: " + (error && error.message ? error.message : ""), "warn");
      return;
    }

    if (!credential) {
      setButtonsLoading(false);
      setStatus("Passkey sign-in was cancelled.", "warn");
      return;
    }

    const finish = await fetchJson(
      "/v1/auth/passkey/login/finish",
      "POST",
      {
        request_id: start.payload.request_id,
        credential: serializeAuthenticationCredential(credential),
      },
      false
    );

    if (!finish.ok) {
      setButtonsLoading(false);
      setStatus("Passkey sign-in failed. Please retry.", "warn");
      return;
    }

    await verifySessionAfterAuth();
  }

  async function signUpWithPasskey() {
    if (!window.PublicKeyCredential) {
      setStatus("This browser does not support passkeys.", "warn");
      return;
    }

    setButtonsLoading(true);
    setStatus("Starting passwordless sign-up...", "warn");

    const start = await fetchJson(
      "/v1/auth/passkey/register/start",
      "POST",
      {
        display_name: "Atlas Masa Member",
        locale: (document.documentElement.lang || "en").slice(0, 2),
      },
      false
    );

    if (!start.ok || !start.payload.options || !start.payload.request_id) {
      setButtonsLoading(false);
      setStatus(
        "Passwordless (more secure) sign up could not start right now.",
        "warn"
      );
      return;
    }

    let credential;
    try {
      const publicKey = prepareRegistrationOptions(start.payload.options);
      credential = await navigator.credentials.create({ publicKey: publicKey });
    } catch (error) {
      setButtonsLoading(false);
      setStatus(
        "Passkey sign-up cancelled: " + (error && error.message ? error.message : ""),
        "warn"
      );
      return;
    }

    if (!credential) {
      setButtonsLoading(false);
      setStatus("Passkey sign-up was cancelled.", "warn");
      return;
    }

    const finish = await fetchJson(
      "/v1/auth/passkey/register/finish",
      "POST",
      {
        request_id: start.payload.request_id,
        credential: serializeRegistrationCredential(credential),
      },
      false
    );

    if (!finish.ok) {
      setButtonsLoading(false);
      setStatus("Passkey sign-up failed. Please retry.", "warn");
      return;
    }

    await signInWithPasskey();
  }

  async function verifySessionAfterAuth() {
    const result = await fetchJson("/v1/auth/me", "GET", undefined, false);
    setButtonsLoading(false);

    if (result.ok && result.payload && result.payload.user) {
      setStatus("Account session is active. Redirecting now...", "ok");
      if (!stayOnAuthPage) {
        window.setTimeout(function () {
          window.location.href = buildPostAuthDestination();
        }, 260);
      }
      return;
    }

    const apiHost = (function () {
      try {
        return new URL(API_BASE).hostname;
      } catch (_error) {
        return "";
      }
    })();
    const onAtlasWeb =
      window.location.hostname === "atlasmasa.com" ||
      window.location.hostname === "www.atlasmasa.com";
    const crossDomainApi = apiHost.endsWith(".up.railway.app");

    if (onAtlasWeb && crossDomainApi) {
      setStatus(
        "Sign-in completed, but session cookie is blocked across domains. Move API to api.atlasmasa.com to unlock persistent account mode.",
        "warn"
      );
      return;
    }

    setStatus("Sign-in completed, but session verification has not propagated yet. Refresh once.", "warn");
  }

  async function redirectIfAlreadyAuthenticated() {
    const result = await fetchJson("/v1/auth/me", "GET", undefined, false);
    if (!(result.ok && result.payload && result.payload.user)) return;
    if (stayOnAuthPage) return;
    setStatus("You are already signed in. Redirecting...", "ok");
    window.setTimeout(function () {
      window.location.href = buildPostAuthDestination();
    }, 220);
  }

  async function applyCapabilities() {
    const result = await fetchJson("/health", "GET", undefined, false);
    if (!result.ok) {
      // Non-blocking check. Do not override active auth flow/status.
      return;
    }

    const caps = (result.payload && result.payload.capabilities) || {};

    if (appleBtn) appleBtn.disabled = !caps.apple_oauth;
    if (googleBtn) googleBtn.disabled = !caps.google_oauth;
    if (passkeySigninBtn) passkeySigninBtn.disabled = !caps.passkey;
    if (passkeySignupBtn) passkeySignupBtn.disabled = !caps.passkey;

    if (!caps.apple_oauth || !caps.google_oauth || !caps.passkey) {
      setStatus("Some auth providers are still being configured on the API.", "warn");
    }
  }

  if (appleBtn) {
    appleBtn.addEventListener("click", function () {
      startOAuth("apple");
    });
  }
  if (googleBtn) {
    googleBtn.addEventListener("click", function () {
      startOAuth("google");
    });
  }
  if (passkeySigninBtn) {
    passkeySigninBtn.addEventListener("click", signInWithPasskey);
  }
  if (passkeySignupBtn) {
    passkeySignupBtn.addEventListener("click", signUpWithPasskey);
  }

  if (authResult === "success") {
    verifySessionAfterAuth();
  } else if (authResult === "error") {
    setStatus("Sign-in failed: " + (authReason || "Unknown reason"), "warn");
  } else {
    redirectIfAlreadyAuthenticated();
  }

  applyCapabilities();
})();
