(function () {
  const DEFAULT_API_BASE = "https://api.atlasmasa.com";
  const API_BASE_STORAGE_KEY = "atlas_api_base";
  const PHOTO_STORAGE_PREFIX = "atlas_profile_photo_data_url_v1";
  const MAX_PHOTO_BYTES = 1_800_000;

  function normalizeApiBase(value) {
    return String(value || "").trim().replace(/\/+$/, "");
  }

  function sanitizeApiBase(value) {
    const normalized = normalizeApiBase(value);
    if (!normalized) return DEFAULT_API_BASE;
    try {
      const url = new URL(normalized);
      const host = (url.hostname || "").toLowerCase();
      if (!/^https?:$/.test(url.protocol)) return DEFAULT_API_BASE;
      if (
        host === "atlasmasa.com" ||
        host === "www.atlasmasa.com" ||
        host === window.location.hostname.toLowerCase()
      ) {
        return DEFAULT_API_BASE;
      }
      return normalizeApiBase(url.toString());
    } catch (_error) {
      return DEFAULT_API_BASE;
    }
  }

  function getApiBase() {
    const params = new URLSearchParams(window.location.search);
    const fromQuery = params.get("api_base");
    if (fromQuery) {
      const normalized = sanitizeApiBase(fromQuery);
      window.localStorage.setItem(API_BASE_STORAGE_KEY, normalized);
      return normalized;
    }
    const fromStorage = window.localStorage.getItem(API_BASE_STORAGE_KEY);
    const normalized = sanitizeApiBase(fromStorage || DEFAULT_API_BASE);
    window.localStorage.setItem(API_BASE_STORAGE_KEY, normalized);
    return normalized;
  }

  async function fetchActiveUser(apiBase) {
    try {
      const response = await fetch(apiBase + "/v1/auth/me", {
        method: "GET",
        headers: { Accept: "application/json" },
        credentials: "include",
      });
      if (!response.ok) return null;
      const text = await response.text();
      const payload = text ? JSON.parse(text) : {};
      if (!payload || !payload.user) return null;
      return payload.user;
    } catch (_error) {
      return null;
    }
  }

  function injectProfileStyles() {
    if (document.getElementById("atlas-auth-nav-style")) return;

    const style = document.createElement("style");
    style.id = "atlas-auth-nav-style";
    style.textContent = `
      .nav__profile {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        flex: 0 0 auto;
      }

      .nav__profile-btn {
        width: 40px;
        height: 40px;
        border-radius: 999px;
        border: 1px solid rgba(255,255,255,.2);
        background: linear-gradient(135deg, rgba(199,53,53,.2), rgba(255,146,83,.15));
        color: #f4f7fc;
        cursor: pointer;
        padding: 0;
        display: inline-grid;
        place-items: center;
        overflow: hidden;
      }

      .nav__profile-btn:hover {
        border-color: rgba(255,255,255,.34);
        background: linear-gradient(135deg, rgba(199,53,53,.34), rgba(255,146,83,.22));
      }

      .nav__profile-img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: none;
      }

      .nav__profile-fallback {
        font-size: 13px;
        font-weight: 800;
        letter-spacing: .04em;
      }

      .nav__profile.nav__profile--has-photo .nav__profile-img {
        display: block;
      }

      .nav__profile.nav__profile--has-photo .nav__profile-fallback {
        display: none;
      }

      .nav__panel .nav__profile {
        width: 100%;
        justify-content: flex-start;
      }
    `;

    document.head.appendChild(style);
  }

  function initialsFromUser(user) {
    const name = String((user && (user.name || user.display_name || user.email)) || "")
      .trim()
      .replace(/\s+/g, " ");
    if (!name) return "A";
    const parts = name.split(" ");
    if (parts.length >= 2) {
      const first = parts[0].charAt(0);
      const second = parts[1].charAt(0);
      const initials = (first + second).toUpperCase();
      return initials || "A";
    }
    return name.charAt(0).toUpperCase() || "A";
  }

  function profilePhotoStorageKey(user) {
    const userId = String(
      (user && (user.user_id || user.userId || user.id || user.email || "default")) || "default"
    ).trim();
    return PHOTO_STORAGE_PREFIX + ":" + userId;
  }

  function loadStoredPhoto(user) {
    const key = profilePhotoStorageKey(user);
    return window.localStorage.getItem(key) || "";
  }

  function storePhoto(user, dataUrl) {
    const key = profilePhotoStorageKey(user);
    window.localStorage.setItem(key, dataUrl);
  }

  function classifyAuthLink(link) {
    if (!link || link.tagName !== "A") return "none";
    const classList = link.classList || { contains: function () { return false; } };
    const i18nKey = String(link.getAttribute("data-i18n") || "").toLowerCase();
    const label = String(link.textContent || "").trim().toLowerCase();

    if (classList.contains("nav__auth--primary") || i18nKey.endsWith(".signup")) {
      return "signup";
    }
    if (classList.contains("nav__auth")) {
      if (i18nKey.endsWith(".concierge") || label.includes("account") || label.includes("חשבון")) {
        return "none";
      }
      return "login";
    }
    if (i18nKey.endsWith(".login")) return "login";

    if (/^sign in$|^log in$|^login$|^התחברות$|^כניסה$/.test(label)) return "login";
    if (/^sign up$|^signup$|^register$|^הרשמה$|^הירשמות$/.test(label)) return "signup";

    return "none";
  }

  function hideLoginAndSignupLinks(navRoot) {
    if (!navRoot) return false;
    let didHide = false;
    const links = navRoot.querySelectorAll("a[href]");
    links.forEach(function (link) {
      const kind = classifyAuthLink(link);
      if (kind === "login" || kind === "signup") {
        link.hidden = true;
        link.style.display = "none";
        link.setAttribute("aria-hidden", "true");
        didHide = true;
      }
    });
    return didHide;
  }

  function mountProfileControl(navRoot, user) {
    if (!navRoot) return;
    if (navRoot.querySelector("[data-atlas-nav-profile='1']")) return;

    const wrapper = document.createElement("div");
    wrapper.className = "nav__profile";
    wrapper.setAttribute("data-atlas-nav-profile", "1");

    const picker = document.createElement("input");
    picker.type = "file";
    picker.accept = "image/*";
    picker.hidden = true;

    const button = document.createElement("button");
    button.type = "button";
    button.className = "nav__profile-btn";
    button.setAttribute("aria-label", "Edit profile photo");
    button.setAttribute("title", "Edit profile photo");

    const photo = document.createElement("img");
    photo.className = "nav__profile-img";
    photo.alt = "Profile photo";

    const fallback = document.createElement("span");
    fallback.className = "nav__profile-fallback";
    fallback.textContent = initialsFromUser(user);

    const savedPhoto = loadStoredPhoto(user);
    if (savedPhoto) {
      photo.src = savedPhoto;
      wrapper.classList.add("nav__profile--has-photo");
    }

    button.addEventListener("click", function () {
      picker.click();
    });

    picker.addEventListener("change", function (event) {
      const input = event.target;
      if (!input || !input.files || input.files.length === 0) return;
      const file = input.files[0];
      if (!file.type || !file.type.startsWith("image/")) return;
      if (file.size > MAX_PHOTO_BYTES) {
        window.alert("Image is too large. Please select a file under 1.8MB.");
        input.value = "";
        return;
      }

      const reader = new FileReader();
      reader.onload = function () {
        const result = String(reader.result || "");
        if (!result) return;
        photo.src = result;
        wrapper.classList.add("nav__profile--has-photo");
        try {
          storePhoto(user, result);
        } catch (_error) {}
      };
      reader.readAsDataURL(file);
      input.value = "";
    });

    button.appendChild(photo);
    button.appendChild(fallback);
    wrapper.appendChild(button);
    wrapper.appendChild(picker);
    navRoot.appendChild(wrapper);
  }

  async function initAuthNav() {
    const navRoots = [
      ...document.querySelectorAll(".header .nav--desktop"),
      ...document.querySelectorAll(".header .nav__panel"),
      ...document.querySelectorAll(".auth-nav"),
    ];
    if (navRoots.length === 0) return;

    const apiBase = getApiBase();
    const user = await fetchActiveUser(apiBase);
    if (!user) return;

    injectProfileStyles();
    navRoots.forEach(function (navRoot) {
      const changed = hideLoginAndSignupLinks(navRoot);
      if (changed) {
        mountProfileControl(navRoot, user);
      }
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initAuthNav);
  } else {
    initAuthNav();
  }
})();
