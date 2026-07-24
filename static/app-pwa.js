"use strict";
(() => {
  // frontend/ts/generated/contracts.ts
  function isPwaInstallState(value) {
    return typeof value === "string" && ["accepted", "dismissed", "failed"].includes(value);
  }
  var pwaInstallPageDomAttr = "data-bepis-pwa-install-page";
  var pwaInstallButtonDomAttr = "data-bepis-pwa-install-button";
  var pwaInstallResultDomAttr = "data-bepis-pwa-install-result";
  var pwaInstallResultStateDomAttr = "data-bepis-pwa-install-result-state";
  var pwaInstalledStatusDomAttr = "data-bepis-pwa-installed-status";

  // frontend/ts/app-pwa.ts
  function parsePwaInstallState(value) {
    if (isPwaInstallState(value)) return value;
    throw new Error("Invalid PwaInstallState");
  }
  var deferredInstallPrompt = null;
  var installationCompleted = false;
  function roleSelector(attribute) {
    return `[${attribute}]`;
  }
  function isBeforeInstallPromptEvent(event) {
    const candidate = event;
    return typeof candidate.prompt === "function" && typeof candidate.userChoice?.then === "function";
  }
  function isStandalone() {
    return window.matchMedia("(display-mode: standalone)").matches || navigator.standalone === true || installationCompleted;
  }
  function installPage() {
    return document.querySelector(roleSelector(pwaInstallPageDomAttr));
  }
  function renderInstallState() {
    const page = installPage();
    if (!page) return;
    const installed = isStandalone();
    const installedStatus = page.querySelector(roleSelector(pwaInstalledStatusDomAttr));
    const installButton = page.querySelector(roleSelector(pwaInstallButtonDomAttr));
    if (installedStatus) installedStatus.hidden = !installed;
    if (installButton) installButton.hidden = installed || deferredInstallPrompt === null;
  }
  function installResultElements(result) {
    const elements = Array.from(
      result.querySelectorAll(roleSelector(pwaInstallResultStateDomAttr))
    );
    const byState = /* @__PURE__ */ new Map();
    for (const element of elements) {
      let state;
      try {
        state = parsePwaInstallState(element.getAttribute(pwaInstallResultStateDomAttr));
      } catch (error) {
        console.error?.("Invalid generated PWA install result state", error);
        return null;
      }
      if (byState.has(state)) {
        console.error?.("Invalid generated PWA install result state", `Duplicate state: ${state}`);
        return null;
      }
      byState.set(state, element);
    }
    return byState;
  }
  function renderInstallResult(page, state) {
    const result = page.querySelector(roleSelector(pwaInstallResultDomAttr));
    if (!result) return;
    const elements = installResultElements(result);
    const selected = elements?.get(state);
    if (!elements || !selected) {
      console.error?.("Invalid generated PWA install result state", `Missing state: ${state}`);
      return;
    }
    for (const element of elements.values()) {
      element.hidden = element !== selected;
    }
  }
  async function promptForInstallation(page) {
    const installPrompt = deferredInstallPrompt;
    if (!installPrompt || isStandalone()) return;
    deferredInstallPrompt = null;
    renderInstallState();
    try {
      await installPrompt.prompt();
      const choice = await installPrompt.userChoice;
      renderInstallResult(page, parsePwaInstallState(choice.outcome));
    } catch {
      renderInstallResult(page, parsePwaInstallState("failed"));
    }
  }
  (function enablePwaInstallation() {
    if (typeof window === "undefined") return;
    window.addEventListener("beforeinstallprompt", (event) => {
      if (!isBeforeInstallPromptEvent(event)) return;
      event.preventDefault();
      deferredInstallPrompt = event;
      renderInstallState();
    });
    window.addEventListener("appinstalled", () => {
      deferredInstallPrompt = null;
      installationCompleted = true;
      renderInstallState();
    });
    document.addEventListener("click", (event) => {
      const target = event.target;
      if (!(target instanceof Element)) return;
      const button = target.closest(roleSelector(pwaInstallButtonDomAttr));
      const page = button?.closest(roleSelector(pwaInstallPageDomAttr));
      if (!button || !page) return;
      void promptForInstallation(page);
    });
    document.addEventListener("DOMContentLoaded", renderInstallState, { once: true });
    if (document.readyState !== "loading") renderInstallState();
  })();
})();
