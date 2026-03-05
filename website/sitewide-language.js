(function () {
  const STORAGE_KEY = "atlas_site_lang";
  const LANGUAGES = [
    { code: "he", label: "עברית", dir: "rtl" },
    { code: "en", label: "English", dir: "ltr" },
    { code: "ar", label: "العربية", dir: "rtl" },
    { code: "ru", label: "Русский", dir: "ltr" },
    { code: "fr", label: "Français", dir: "ltr" }
  ];

  let current = "he";
  let container = null;
  let languageSelect = null;
  const FAVICON_PATH = "/favicon.svg";

  function getByPath(objectValue, path) {
    if (!objectValue || !path) return undefined;
    return path.split(".").reduce((acc, key) => {
      if (acc && Object.prototype.hasOwnProperty.call(acc, key)) {
        return acc[key];
      }
      return undefined;
    }, objectValue);
  }

  function resolveTranslation(dictionaries, lang, key) {
    const byLang = dictionaries[lang] || dictionaries.he || {};
    const fallback = dictionaries.he || {};
    const value = getByPath(byLang, key);
    if (value !== undefined && value !== null) return value;
    return getByPath(fallback, key);
  }

  function applyPageTranslations(lang) {
    const dictionaries = window.ATLAS_PAGE_I18N;
    if (!dictionaries) return;

    const pageTitle = resolveTranslation(dictionaries, lang, "meta.title");
    if (typeof pageTitle === "string" && pageTitle.trim()) {
      document.title = pageTitle;
    }

    const pageDescription = resolveTranslation(dictionaries, lang, "meta.description");
    if (typeof pageDescription === "string" && pageDescription.trim()) {
      const description = document.querySelector('meta[name="description"]');
      if (description) description.setAttribute("content", pageDescription);
    }

    document.querySelectorAll("[data-i18n]").forEach((element) => {
      const key = element.getAttribute("data-i18n");
      if (!key) return;
      const value = resolveTranslation(dictionaries, lang, key);
      if (typeof value === "string") {
        element.textContent = value;
      }
    });

    document.querySelectorAll("[data-i18n-html]").forEach((element) => {
      const key = element.getAttribute("data-i18n-html");
      if (!key) return;
      const value = resolveTranslation(dictionaries, lang, key);
      if (typeof value === "string") {
        element.innerHTML = value;
      }
    });

    document.querySelectorAll("[data-i18n-placeholder]").forEach((element) => {
      const key = element.getAttribute("data-i18n-placeholder");
      if (!key) return;
      const value = resolveTranslation(dictionaries, lang, key);
      if (typeof value === "string") {
        element.setAttribute("placeholder", value);
      }
    });

    document.querySelectorAll("[data-i18n-aria-label]").forEach((element) => {
      const key = element.getAttribute("data-i18n-aria-label");
      if (!key) return;
      const value = resolveTranslation(dictionaries, lang, key);
      if (typeof value === "string") {
        element.setAttribute("aria-label", value);
      }
    });

    document.querySelectorAll("[data-i18n-title]").forEach((element) => {
      const key = element.getAttribute("data-i18n-title");
      if (!key) return;
      const value = resolveTranslation(dictionaries, lang, key);
      if (typeof value === "string") {
        element.setAttribute("title", value);
      }
    });

    window.dispatchEvent(
      new CustomEvent("atlas:translations-applied", {
        detail: { code: lang }
      })
    );
  }

  function injectStyles() {
    if (document.getElementById("atlas-lang-style")) return;

    const style = document.createElement("style");
    style.id = "atlas-lang-style";
    style.textContent = `
      .atlas-lang-switcher {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        max-width: 100%;
        padding: 8px 10px;
        border-radius: 14px;
        border: 1px solid rgba(255,255,255,.14);
        backdrop-filter: blur(12px);
        background: rgba(7, 11, 20, .72);
        box-shadow: 0 12px 28px rgba(0,0,0,.28);
      }

      .header .header__inner > .atlas-lang-switcher:not(.atlas-lang-switcher--floating),
      .auth-header .auth-header__inner > .atlas-lang-switcher:not(.atlas-lang-switcher--floating) {
        flex: 0 0 100%;
        order: 3;
        justify-content: space-between;
        margin-top: 6px;
      }

      .atlas-lang-switcher--floating {
        position: fixed;
        inset-inline-start: 14px;
        bottom: 14px;
        z-index: 9999;
        width: min(92vw, 340px);
      }

      .atlas-lang-switcher--in-menu {
        width: 100%;
        margin-top: 8px;
        box-shadow: none;
      }

      .atlas-lang-head {
        font-size: 11px;
        font-weight: 800;
        color: rgba(243,246,255,.84);
        white-space: nowrap;
      }

      .atlas-lang-field {
        flex: 1;
        min-width: 0;
      }

      .atlas-lang-select {
        width: 100%;
        border: 1px solid rgba(255,255,255,.14);
        border-radius: 10px;
        background-color: rgba(255,255,255,.03);
        color: #f3f6ff;
        font-size: 12px;
        font-weight: 800;
        line-height: 1.2;
        padding: 7px 28px 7px 10px;
        cursor: pointer;
        appearance: none;
        background-image:
          linear-gradient(45deg, transparent 50%, rgba(243,246,255,.92) 50%),
          linear-gradient(135deg, rgba(243,246,255,.92) 50%, transparent 50%);
        background-position:
          calc(100% - 14px) 50%,
          calc(100% - 9px) 50%;
        background-size: 5px 5px, 5px 5px;
        background-repeat: no-repeat;
      }

      .atlas-lang-select:focus {
        outline: 2px solid rgba(124,92,255,.65);
        outline-offset: 1px;
      }

      .atlas-lang-select option {
        color: #0d1321;
      }

      @media (max-width: 1180px) {
        .atlas-lang-switcher:not(.atlas-lang-switcher--floating) {
          width: 100%;
          justify-content: space-between;
          margin-top: 6px;
        }
      }

      @media (max-width: 620px) {
        .atlas-lang-switcher--floating {
          bottom: 10px;
          inset-inline-start: 10px;
          width: calc(100vw - 20px);
        }
      }
    `;

    document.head.appendChild(style);
  }

  function ensureFavicon() {
    if (!document || !document.head) return;
    let icon = document.querySelector('link[rel="icon"]');
    if (!icon) {
      icon = document.createElement("link");
      icon.setAttribute("rel", "icon");
      document.head.appendChild(icon);
    }
    icon.setAttribute("type", "image/svg+xml");
    icon.setAttribute("href", FAVICON_PATH);
  }

  function applyLanguage(code, persist) {
    const selected = LANGUAGES.find((language) => language.code === code) || LANGUAGES[0];
    current = selected.code;

    if (persist) {
      try {
        localStorage.setItem(STORAGE_KEY, current);
      } catch (_) {}
    }

    document.documentElement.setAttribute("lang", current);
    document.documentElement.setAttribute("dir", selected.dir);

    if (languageSelect && languageSelect.value !== current) {
      languageSelect.value = current;
    }

    applyPageTranslations(current);
    window.dispatchEvent(new CustomEvent("atlas:language-change", { detail: { code: current } }));
  }

  function injectUI() {
    const existing = document.querySelector(".atlas-lang-switcher");
    if (existing) {
      container = existing;
      languageSelect = existing.querySelector("select[data-lang-select]");
      return;
    }

    const headerMount =
      document.querySelector(".header .header__inner") ||
      document.querySelector(".auth-header .auth-header__inner");
    const mobileMenuMount = document.querySelector(".nav--mobile .nav__panel");
    const mobileMenuDetails =
      mobileMenuMount && mobileMenuMount.parentElement && mobileMenuMount.parentElement.tagName === "DETAILS"
        ? mobileMenuMount.parentElement
        : null;
    const useFloating = !headerMount && !mobileMenuMount;

    container = document.createElement("aside");
    container.className = useFloating
      ? "atlas-lang-switcher atlas-lang-switcher--floating"
      : "atlas-lang-switcher";
    container.setAttribute("aria-label", "Language switcher");

    const head = document.createElement("div");
    head.className = "atlas-lang-head";
    head.textContent = "שפה / Language";

    const field = document.createElement("label");
    field.className = "atlas-lang-field";
    field.setAttribute("for", "atlas-lang-select");

    languageSelect = document.createElement("select");
    languageSelect.id = "atlas-lang-select";
    languageSelect.className = "atlas-lang-select";
    languageSelect.dataset.langSelect = "true";
    languageSelect.setAttribute("aria-label", "Choose language");

    for (const language of LANGUAGES) {
      const option = document.createElement("option");
      option.value = language.code;
      option.textContent = language.label;
      languageSelect.appendChild(option);
    }

    languageSelect.addEventListener("change", () => {
      applyLanguage(languageSelect.value, true);
      if (mobileMenuDetails) {
        mobileMenuDetails.removeAttribute("open");
      }
    });

    field.appendChild(languageSelect);
    container.appendChild(head);
    container.appendChild(field);

    container.classList.remove("atlas-lang-switcher--floating", "atlas-lang-switcher--in-menu");
    if (mobileMenuMount) {
      mobileMenuMount.appendChild(container);
      container.classList.add("atlas-lang-switcher--in-menu");
      if (mobileMenuDetails) {
        mobileMenuDetails.removeAttribute("open");
      }
    } else if (headerMount) {
      headerMount.appendChild(container);
    } else {
      container.classList.add("atlas-lang-switcher--floating");
      document.body.appendChild(container);
    }

    if (mobileMenuMount && mobileMenuDetails) {
      mobileMenuMount.addEventListener("click", (event) => {
        const target = event.target;
        if (!target || !(target.matches && target.matches("a"))) return;
        mobileMenuDetails.removeAttribute("open");
      });
    }
  }

  function init() {
    ensureFavicon();
    injectStyles();
    const uiMode =
      (document.body && document.body.getAttribute("data-language-switcher")) || "on";
    const disableSwitcher = uiMode.toLowerCase() === "off";
    if (!disableSwitcher) {
      injectUI();
    }

    let preferred = "he";
    try {
      preferred = localStorage.getItem(STORAGE_KEY) || document.documentElement.lang || "he";
    } catch (_) {
      preferred = document.documentElement.lang || "he";
    }

    applyLanguage(preferred, false);
  }

  window.AtlasLanguage = {
    getCurrent: function () {
      return current;
    },
    set: function (code) {
      applyLanguage(code, true);
    },
    supported: LANGUAGES.map((language) => language.code),
    refreshTranslations: function () {
      applyPageTranslations(current);
    }
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
