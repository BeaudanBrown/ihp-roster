"use strict";
(() => {
  // frontend/ts/generated/contracts.ts
  function isRecord(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
  }
  function hasExactKeys(value, keys, requiredKeys = keys) {
    const valueKeys = Object.keys(value);
    return valueKeys.every((key) => keys.includes(key)) && requiredKeys.every((key) => Object.prototype.hasOwnProperty.call(value, key));
  }
  var pageReadyEvent = "bepis:page-ready";
  function isDialogSubmitConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["loadingLabel"], ["loadingLabel"]) && typeof value["loadingLabel"] === "string";
  }
  function parseDialogSubmitConfig(value) {
    if (isDialogSubmitConfig(value)) return value;
    throw new Error("Invalid DialogSubmitConfig");
  }
  var dialogOverlayMountDomId = "dialog-overlay-mount";
  var dialogMountDomAttr = "data-bepis-dialog-mount";
  var dialogBackdropDomAttr = "data-bepis-dialog-backdrop";
  var dialogCloseDomAttr = "data-bepis-dialog-close";
  var dialogSubmitDomAttr = "data-bepis-dialog-submit";
  var dialogSubmitConfigDomAttr = "data-bepis-dialog-submit-config";
  var dialogAutoSubmitOnceDomAttr = "data-bepis-dialog-auto-submit-once";

  // frontend/ts/shared/dom.ts
  function isElement(value) {
    return typeof Element !== "undefined" && value instanceof Element;
  }
  function isHTMLElement(value) {
    return typeof HTMLElement !== "undefined" && value instanceof HTMLElement;
  }
  function closestHTMLElement(target, selector) {
    if (!isElement(target)) return null;
    const element = target.closest(selector);
    return isHTMLElement(element) ? element : null;
  }

  // frontend/ts/shared/lifecycle.ts
  function eventDetailRecord(event) {
    if (typeof CustomEvent === "undefined" || !(event instanceof CustomEvent)) return null;
    if (event.detail === null || typeof event.detail !== "object") return null;
    return event.detail;
  }
  function detailTarget(event, key) {
    return eventDetailRecord(event)?.[key];
  }

  // frontend/ts/app-dialog-overlays.ts
  var dialogMountSelector = `[${dialogMountDomAttr}]`;
  var dialogBackdropSelector = `[${dialogBackdropDomAttr}]`;
  var dialogCloseSelector = `[${dialogCloseDomAttr}]`;
  var autoSubmittedForms = /* @__PURE__ */ new WeakSet();
  var originalSubmitHtml = /* @__PURE__ */ new WeakMap();
  function dialogSubmitLoadingHtml(label) {
    return '<span class="spinner-border spinner-border-sm" aria-hidden="true"></span><span>' + label + "</span>";
  }
  function parseDialogSubmitConfiguration(raw) {
    const config = parseDialogSubmitConfig(JSON.parse(raw));
    if (config.loadingLabel.trim().length === 0) {
      throw new Error("DialogSubmitConfig loadingLabel must not be empty");
    }
    return config;
  }
  function dialogSubmitConfiguration(submitter) {
    const rawConfig = submitter.getAttribute(dialogSubmitConfigDomAttr);
    try {
      if (rawConfig === null) throw new Error(`Missing ${dialogSubmitConfigDomAttr}`);
      return parseDialogSubmitConfiguration(rawConfig);
    } catch (error) {
      console.error?.("Invalid generated dialog submit configuration", {
        code: "invalid-dialog-submit-config",
        message: error instanceof Error ? error.message : String(error)
      });
      return null;
    }
  }
  (function enableDialogOverlayMount() {
    if (typeof window === "undefined") return;
    const mountId = dialogOverlayMountDomId;
    function getMount() {
      const mountEl = document.getElementById(mountId);
      return isHTMLElement(mountEl) ? mountEl : null;
    }
    function getActiveDialog() {
      const mountEl = getMount();
      if (mountEl === null) return null;
      const dialogEl = mountEl.querySelector(dialogMountSelector);
      return isHTMLElement(dialogEl) ? dialogEl : null;
    }
    function hasVisibleBootstrapModal() {
      return Boolean(document.querySelector(`.modal.show:not(${dialogMountSelector})`));
    }
    function syncDialogState() {
      const dialogEl = getActiveDialog();
      const hasDialog = dialogEl instanceof HTMLElement;
      const shouldLockBody = hasDialog || hasVisibleBootstrapModal();
      document.body.classList.toggle("modal-open", shouldLockBody);
      document.body.style.overflow = shouldLockBody ? "hidden" : "";
    }
    function clearMount() {
      const mountEl = getMount();
      if (mountEl === null) return;
      mountEl.innerHTML = "";
      syncDialogState();
    }
    function submitAutoFormsOnce(container) {
      container.querySelectorAll(`form[${dialogAutoSubmitOnceDomAttr}]`).forEach(function(form) {
        if (!(form instanceof HTMLFormElement)) return;
        if (autoSubmittedForms.has(form)) return;
        autoSubmittedForms.add(form);
        form.requestSubmit();
      });
    }
    document.addEventListener("click", function(event) {
      const activeDialog = getActiveDialog();
      const closeEl = closestHTMLElement(event.target, dialogCloseSelector);
      if (closeEl !== null && activeDialog !== null) {
        event.preventDefault();
        clearMount();
        return;
      }
      const backdropEl = closestHTMLElement(event.target, dialogBackdropSelector);
      if (backdropEl !== null && activeDialog !== null) {
        event.preventDefault();
        clearMount();
        return;
      }
      if (activeDialog !== null && event.target === activeDialog) {
        event.preventDefault();
        clearMount();
      }
    });
    document.addEventListener("keydown", function(event) {
      if (event.key !== "Escape") return;
      if (getActiveDialog() === null) return;
      event.preventDefault();
      clearMount();
    });
    document.addEventListener("submit", function(event) {
      const activeDialog = getActiveDialog();
      if (activeDialog === null) return;
      const form = event.target;
      if (!(form instanceof HTMLFormElement)) return;
      const submitter = event instanceof SubmitEvent ? event.submitter : null;
      if (!(submitter instanceof HTMLButtonElement)) return;
      if (!submitter.hasAttribute(dialogSubmitDomAttr)) return;
      const config = dialogSubmitConfiguration(submitter);
      if (config === null) return;
      activeDialog.querySelectorAll("button, a.btn").forEach(function(control) {
        if (control instanceof HTMLButtonElement) {
          control.disabled = true;
        } else if (isHTMLElement(control)) {
          control.classList.add("disabled");
          control.setAttribute("aria-disabled", "true");
        }
      });
      if (!originalSubmitHtml.has(submitter)) {
        originalSubmitHtml.set(submitter, submitter.innerHTML);
      }
      submitter.innerHTML = dialogSubmitLoadingHtml(config.loadingLabel);
      submitter.classList.add("d-inline-flex", "align-items-center", "gap-2");
    }, true);
    document.addEventListener("htmx:afterRequest", function(event) {
      const activeDialog = getActiveDialog();
      if (activeDialog === null) return;
      const elt = detailTarget(event, "elt");
      if (!isHTMLElement(elt)) return;
      if (!activeDialog.contains(elt)) return;
      activeDialog.querySelectorAll("button, a.btn").forEach(function(control) {
        if (control instanceof HTMLButtonElement) {
          control.disabled = false;
        } else if (isHTMLElement(control)) {
          control.classList.remove("disabled");
          control.removeAttribute("aria-disabled");
        }
      });
      activeDialog.querySelectorAll(`[${dialogSubmitDomAttr}]`).forEach(function(control) {
        if (!(control instanceof HTMLButtonElement)) return;
        const originalHtml = originalSubmitHtml.get(control);
        if (originalHtml !== void 0) {
          control.innerHTML = originalHtml;
        }
        control.classList.remove("d-inline-flex", "align-items-center", "gap-2");
      });
    });
    document.addEventListener("htmx:afterSwap", function(event) {
      const target = detailTarget(event, "target");
      if (!isHTMLElement(target)) return;
      if (target.id !== mountId) return;
      window.htmx?.process?.(target);
      submitAutoFormsOnce(target);
      syncDialogState();
    });
    document.addEventListener("htmx:oobAfterSwap", function(event) {
      const target = detailTarget(event, "target");
      if (!isHTMLElement(target)) return;
      if (target.id !== mountId) return;
      submitAutoFormsOnce(target);
      syncDialogState();
    });
    document.addEventListener("shown.bs.modal", syncDialogState);
    document.addEventListener("hidden.bs.modal", syncDialogState);
    document.addEventListener(pageReadyEvent, syncDialogState);
  })();
})();
