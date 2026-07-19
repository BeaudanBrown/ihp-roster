"use strict";
(() => {
  // frontend/ts/generated/contracts.ts
  function isRecord(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
  }
  function hasExactKeys(value, keys) {
    return Object.keys(value).every((key) => keys.includes(key));
  }
  var pageReadyEvent = "bepis:page-ready";
  function isToastConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["autoHideMs"]) && (typeof value["autoHideMs"] === "number" && Number.isInteger(value["autoHideMs"]));
  }
  function parseToastConfig(value) {
    if (isToastConfig(value)) return value;
    throw new Error("Invalid ToastConfig");
  }
  var toastOverlayMountDomId = "toast-overlay-mount";
  var toastMountDomAttr = "data-bepis-toast-mount";
  var toastCloseDomAttr = "data-bepis-toast-close";
  var toastConfigDomAttr = "data-bepis-toast-config";

  // frontend/ts/app-toasts.ts
  var hostId = toastOverlayMountDomId;
  var toastMountSelector = `[${toastMountDomAttr}]`;
  var toastCloseSelector = `[${toastCloseDomAttr}]`;
  var initializedToasts = /* @__PURE__ */ new WeakSet();
  function parseToastConfiguration(raw) {
    const config = parseToastConfig(JSON.parse(raw));
    if (config.autoHideMs < 0) {
      throw new Error("ToastConfig autoHideMs must not be negative");
    }
    return config;
  }
  function getHost() {
    return document.getElementById(hostId);
  }
  function dismissToast(toastEl) {
    toastEl.classList.add("app-toast-leaving");
    window.setTimeout(() => {
      if (toastEl.parentNode !== null) {
        toastEl.remove();
      }
    }, 220);
  }
  function initToast(toastEl) {
    if (initializedToasts.has(toastEl)) return;
    initializedToasts.add(toastEl);
    const rawConfig = toastEl.getAttribute(toastConfigDomAttr);
    let config;
    try {
      if (rawConfig === null) throw new Error(`Missing ${toastConfigDomAttr}`);
      config = parseToastConfiguration(rawConfig);
    } catch (error) {
      console.error?.("Invalid generated toast configuration", {
        code: "invalid-toast-config",
        message: error instanceof Error ? error.message : String(error)
      });
      return;
    }
    if (config.autoHideMs > 0) {
      window.setTimeout(() => {
        dismissToast(toastEl);
      }, config.autoHideMs);
    }
  }
  function initHostToasts() {
    const hostEl = getHost();
    if (!(hostEl instanceof HTMLElement)) return;
    hostEl.querySelectorAll(toastMountSelector).forEach(initToast);
  }
  function enableToastOverlayHost() {
    if (typeof window === "undefined") return;
    document.addEventListener("click", (event) => {
      if (!(event.target instanceof Element)) return;
      const closeEl = event.target.closest(toastCloseSelector);
      if (!(closeEl instanceof HTMLElement)) return;
      const toastEl = closeEl.closest(toastMountSelector);
      if (toastEl instanceof HTMLElement) {
        dismissToast(toastEl);
      }
    });
    document.addEventListener(pageReadyEvent, initHostToasts);
  }
  enableToastOverlayHost();
})();
