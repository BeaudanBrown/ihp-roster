"use strict";
(() => {
  // frontend/ts/app-toasts.ts
  var hostId = "toast-overlay-mount";
  var initializedKey = "toastInitialized";
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
    if (toastEl.dataset[initializedKey] === "true") return;
    toastEl.dataset[initializedKey] = "true";
    const autoHideMs = Number.parseInt(toastEl.dataset.autoHideMs ?? "0", 10);
    if (autoHideMs > 0) {
      window.setTimeout(() => {
        dismissToast(toastEl);
      }, autoHideMs);
    }
  }
  function initHostToasts() {
    const hostEl = getHost();
    if (!(hostEl instanceof HTMLElement)) return;
    hostEl.querySelectorAll('[data-overlay-toast="true"]').forEach(initToast);
  }
  function enableToastOverlayHost() {
    if (typeof window === "undefined") return;
    document.addEventListener("click", (event) => {
      if (!(event.target instanceof Element)) return;
      const closeEl = event.target.closest('[data-toast-close="true"]');
      if (!(closeEl instanceof HTMLElement)) return;
      const toastEl = closeEl.closest('[data-overlay-toast="true"]');
      if (toastEl instanceof HTMLElement) {
        dismissToast(toastEl);
      }
    });
    document.addEventListener("app:page-ready", initHostToasts);
  }
  enableToastOverlayHost();
})();
