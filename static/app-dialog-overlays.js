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
  function isNavigationLoadingConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["loadingTitle", "loadingMessage"], ["loadingTitle", "loadingMessage"]) && typeof value["loadingTitle"] === "string" && typeof value["loadingMessage"] === "string";
  }
  function parseNavigationLoadingConfig(value) {
    if (isNavigationLoadingConfig(value)) return value;
    throw new Error("Invalid NavigationLoadingConfig");
  }
  var dialogOverlayMountDomId = "dialog-overlay-mount";
  var dialogDismissedEvent = "bepis:dialog-dismissed";
  var dialogMountDomAttr = "data-bepis-dialog-mount";
  var dialogBackdropDomAttr = "data-bepis-dialog-backdrop";
  var dialogCloseDomAttr = "data-bepis-dialog-close";
  var dialogSubmitDomAttr = "data-bepis-dialog-submit";
  var dialogSubmitConfigDomAttr = "data-bepis-dialog-submit-config";
  var dialogAutoSubmitOnceDomAttr = "data-bepis-dialog-auto-submit-once";
  var dialogBlockingDomAttr = "data-bepis-dialog-blocking";
  var dialogKeyboardDomAttr = "data-bepis-dialog-keyboard";
  var dialogFocusRegionDomAttr = "data-bepis-dialog-focus-region";
  var navigationLoadingDomAttr = "data-bepis-navigation-loading";
  var navigationLoadingConfigDomAttr = "data-bepis-navigation-loading-config";

  // frontend/ts/shared/dom.ts
  function isElement(value) {
    return typeof Element !== "undefined" && value instanceof Element;
  }
  function isDocument(value) {
    return typeof Document !== "undefined" && value instanceof Document;
  }
  function isDocumentFragment(value) {
    return typeof DocumentFragment !== "undefined" && value instanceof DocumentFragment;
  }
  function isDomRoot(value) {
    return isElement(value) || isDocument(value) || isDocumentFragment(value);
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
  function isConnectedRoot(root) {
    return root instanceof Document || root.isConnected;
  }
  function detailRoot(event, key, fallback = document) {
    const detailCandidate = detailTarget(event, key);
    if (isDomRoot(detailCandidate) && isConnectedRoot(detailCandidate)) return detailCandidate;
    if (isDomRoot(event.target) && isConnectedRoot(event.target)) return event.target;
    return fallback;
  }

  // frontend/ts/app-dialog-overlays.ts
  var dialogMountSelector = `[${dialogMountDomAttr}]`;
  var dialogKeyboardSelector = `[${dialogKeyboardDomAttr}]`;
  var dialogFocusRegionSelector = `[${dialogFocusRegionDomAttr}]`;
  var dialogBackdropSelector = `[${dialogBackdropDomAttr}]`;
  var dialogCloseSelector = `[${dialogCloseDomAttr}]`;
  var navigationLoadingSelector = `form[${navigationLoadingDomAttr}]`;
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
  function parseNavigationLoadingConfiguration(raw) {
    const config = parseNavigationLoadingConfig(JSON.parse(raw));
    if (config.loadingTitle.trim().length === 0) {
      throw new Error("NavigationLoadingConfig loadingTitle must not be empty");
    }
    if (config.loadingMessage.trim().length === 0) {
      throw new Error("NavigationLoadingConfig loadingMessage must not be empty");
    }
    return config;
  }
  function navigationLoadingConfiguration(form) {
    const rawConfig = form.getAttribute(navigationLoadingConfigDomAttr);
    try {
      if (rawConfig === null) throw new Error(`Missing ${navigationLoadingConfigDomAttr}`);
      return parseNavigationLoadingConfiguration(rawConfig);
    } catch (error) {
      console.error?.("Invalid generated navigation loading configuration", {
        code: "invalid-navigation-loading-config",
        message: error instanceof Error ? error.message : String(error)
      });
      return null;
    }
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
    const blockingBackgroundInertStates = /* @__PURE__ */ new Map();
    let blockingDialogReturnFocus = null;
    function getMount() {
      const mountEl = document.getElementById(mountId);
      return isHTMLElement(mountEl) ? mountEl : null;
    }
    function getActiveDialog() {
      const dialogs = Array.from(document.querySelectorAll(dialogMountSelector)).filter(isHTMLElement);
      return dialogs.length === 0 ? null : dialogs[dialogs.length - 1];
    }
    function keyboardFocusRegion(dialog) {
      if (!dialog.matches(dialogKeyboardSelector)) return null;
      const regions = Array.from(dialog.querySelectorAll(dialogFocusRegionSelector));
      return regions.length === 1 && regions[0] instanceof HTMLElement ? regions[0] : null;
    }
    function focusableDialogControls(region) {
      const selector = [
        "input:not([type='hidden']):not([disabled])",
        "select:not([disabled])",
        "textarea:not([disabled])",
        "button:not([disabled])",
        "a[href]",
        "[contenteditable='true']",
        "[tabindex]:not([tabindex='-1'])"
      ].join(",");
      return Array.from(region.querySelectorAll(selector)).filter((element) => {
        if (!(element instanceof HTMLElement)) return false;
        if (element.hidden || element.closest("[hidden], [inert]") !== null) return false;
        return element.tabIndex >= 0;
      });
    }
    function focusKeyboardDialog(dialog) {
      const region = keyboardFocusRegion(dialog);
      if (region === null) return;
      const controls = focusableDialogControls(region);
      const firstInvalid = controls.find((control) => control.getAttribute("aria-invalid") === "true");
      const autofocus = controls.find((control) => control.hasAttribute("autofocus"));
      (firstInvalid ?? autofocus ?? controls[0] ?? dialog).focus({ preventScroll: true });
    }
    function initializeKeyboardDialogs(root) {
      if (root instanceof HTMLElement && root.matches(dialogKeyboardSelector)) focusKeyboardDialog(root);
      root.querySelectorAll(dialogKeyboardSelector).forEach((dialog) => {
        if (dialog instanceof HTMLElement) focusKeyboardDialog(dialog);
      });
    }
    function hasVisibleBootstrapModal() {
      return Boolean(document.querySelector(`.modal.show:not(${dialogMountSelector})`));
    }
    function syncDialogState() {
      const hasDialog = getActiveDialog() !== null;
      const shouldLockBody = hasDialog || hasVisibleBootstrapModal();
      document.body.classList.toggle("modal-open", shouldLockBody);
      document.body.style.overflow = shouldLockBody ? "hidden" : "";
    }
    function showNavigationLoadingDialog(config) {
      const mountEl = getMount();
      if (mountEl === null) return;
      const dialogEl = document.createElement("div");
      dialogEl.className = "modal fade show d-block";
      dialogEl.setAttribute(dialogMountDomAttr, "true");
      dialogEl.setAttribute(dialogBlockingDomAttr, "true");
      dialogEl.setAttribute("tabindex", "-1");
      dialogEl.setAttribute("role", "dialog");
      dialogEl.setAttribute("aria-modal", "true");
      dialogEl.setAttribute("aria-label", config.loadingTitle);
      const modalDialog = document.createElement("div");
      modalDialog.className = "modal-dialog modal-dialog-centered";
      modalDialog.setAttribute("role", "document");
      const content = document.createElement("div");
      content.className = "modal-content shadow";
      const body = document.createElement("div");
      body.className = "modal-body d-flex align-items-center gap-3 py-4";
      body.setAttribute("role", "status");
      body.setAttribute("aria-live", "polite");
      const spinner = document.createElement("span");
      spinner.className = "spinner-border text-primary";
      spinner.setAttribute("aria-hidden", "true");
      const copy = document.createElement("div");
      const title = document.createElement("h2");
      title.className = "h5 mb-1";
      title.textContent = config.loadingTitle;
      const message = document.createElement("p");
      message.className = "mb-0 app-muted";
      message.textContent = config.loadingMessage;
      copy.append(title, message);
      body.append(spinner, copy);
      content.append(body);
      modalDialog.append(content);
      dialogEl.append(modalDialog);
      const backdrop = document.createElement("div");
      backdrop.className = "modal-backdrop fade show";
      backdrop.setAttribute(dialogBackdropDomAttr, "true");
      blockingDialogReturnFocus = isHTMLElement(document.activeElement) ? document.activeElement : null;
      mountEl.replaceChildren(dialogEl, backdrop);
      setBlockingBackgroundInert(mountEl, true);
      syncDialogState();
      dialogEl.focus();
    }
    function setBlockingBackgroundInert(mountEl, inert) {
      Array.from(document.body.children).forEach((element) => {
        if (!(element instanceof HTMLElement) || element === mountEl) return;
        if (inert) {
          if (!blockingBackgroundInertStates.has(element)) {
            blockingBackgroundInertStates.set(element, element.inert);
          }
          element.inert = true;
          return;
        }
        const previous = blockingBackgroundInertStates.get(element);
        if (previous !== void 0) element.inert = previous;
        blockingBackgroundInertStates.delete(element);
      });
    }
    function clearDialog(dialogEl) {
      dialogEl.dispatchEvent(new CustomEvent(dialogDismissedEvent, { bubbles: true }));
      const mountEl = getMount();
      const wasBlocking = dialogEl.hasAttribute(dialogBlockingDomAttr);
      if (wasBlocking && mountEl !== null) setBlockingBackgroundInert(mountEl, false);
      const returnFocus = wasBlocking ? blockingDialogReturnFocus : null;
      if (wasBlocking) blockingDialogReturnFocus = null;
      if (mountEl !== null && mountEl.contains(dialogEl)) {
        mountEl.innerHTML = "";
        syncDialogState();
        if (returnFocus?.isConnected) returnFocus.focus();
        return;
      }
      const localOwner = dialogEl.parentElement;
      dialogEl.remove();
      if (localOwner !== null) {
        Array.from(localOwner.children).forEach((element) => {
          if (element.matches(dialogBackdropSelector)) element.remove();
        });
      }
      syncDialogState();
      if (returnFocus?.isConnected) returnFocus.focus();
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
      const closeEl = closestHTMLElement(event.target, dialogCloseSelector);
      const closeDialog = closeEl?.closest(dialogMountSelector);
      if (closeEl !== null && isHTMLElement(closeDialog)) {
        event.preventDefault();
        clearDialog(closeDialog);
        return;
      }
      const backdropEl = closestHTMLElement(event.target, dialogBackdropSelector);
      const backdropDialog = backdropEl?.parentElement?.querySelector(dialogMountSelector);
      if (backdropEl !== null && isHTMLElement(backdropDialog)) {
        event.preventDefault();
        if (backdropDialog.hasAttribute(dialogBlockingDomAttr)) return;
        clearDialog(backdropDialog);
        return;
      }
      const activeDialog = getActiveDialog();
      if (activeDialog !== null && event.target === activeDialog) {
        event.preventDefault();
        if (activeDialog.hasAttribute(dialogBlockingDomAttr)) return;
        clearDialog(activeDialog);
      }
    });
    document.addEventListener("keydown", function(event) {
      const activeDialog = getActiveDialog();
      if (activeDialog === null) return;
      if (event.key === "Tab" && activeDialog.hasAttribute(dialogBlockingDomAttr)) {
        event.preventDefault();
        activeDialog.focus();
        return;
      }
      const focusRegion = keyboardFocusRegion(activeDialog);
      if (event.key === "Tab" && focusRegion !== null) {
        const controls = focusableDialogControls(focusRegion);
        event.preventDefault();
        if (controls.length === 0) {
          activeDialog.focus();
          return;
        }
        const currentIndex = controls.indexOf(document.activeElement);
        const nextIndex = event.shiftKey ? currentIndex <= 0 ? controls.length - 1 : currentIndex - 1 : currentIndex < 0 || currentIndex === controls.length - 1 ? 0 : currentIndex + 1;
        controls[nextIndex]?.focus();
        return;
      }
      if (event.key === "Enter" && focusRegion !== null && !event.isComposing && !event.ctrlKey && !event.metaKey && !event.altKey) {
        const target = event.target;
        if (target instanceof HTMLTextAreaElement || target instanceof HTMLElement && target.isContentEditable) return;
        const submitter = activeDialog.querySelector(`[${dialogSubmitDomAttr}]`);
        if (submitter instanceof HTMLButtonElement && !submitter.disabled && submitter.form !== null) {
          event.preventDefault();
          submitter.form.requestSubmit(submitter);
        }
        return;
      }
      if (event.key !== "Escape") return;
      event.preventDefault();
      if (!activeDialog.hasAttribute(dialogBlockingDomAttr)) clearDialog(activeDialog);
    });
    document.addEventListener("submit", function(event) {
      if (event.defaultPrevented) return;
      const submittedForm = event.target;
      if (submittedForm instanceof HTMLFormElement && submittedForm.matches(navigationLoadingSelector)) {
        const navigationConfig = navigationLoadingConfiguration(submittedForm);
        if (navigationConfig !== null) showNavigationLoadingDialog(navigationConfig);
      }
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
    });
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
      const target = detailRoot(event, "target");
      if (!isHTMLElement(target)) return;
      if (target.id !== mountId) return;
      window.htmx?.process?.(target);
      submitAutoFormsOnce(target);
      initializeKeyboardDialogs(target);
      syncDialogState();
    });
    document.addEventListener("htmx:oobAfterSwap", function(event) {
      const target = detailRoot(event, "target");
      if (!isHTMLElement(target)) return;
      if (target.id !== mountId) return;
      submitAutoFormsOnce(target);
      initializeKeyboardDialogs(target);
      syncDialogState();
    });
    window.addEventListener("pageshow", function(event) {
      if (!event.persisted) return;
      const activeDialog = getActiveDialog();
      if (activeDialog !== null && activeDialog.hasAttribute(dialogBlockingDomAttr)) {
        clearDialog(activeDialog);
      }
    });
    document.addEventListener("shown.bs.modal", syncDialogState);
    document.addEventListener("hidden.bs.modal", syncDialogState);
    document.addEventListener(pageReadyEvent, (event) => {
      syncDialogState();
      const target = detailTarget(event, "target");
      if (target instanceof HTMLElement || target instanceof Document) initializeKeyboardDialogs(target);
    });
  })();
})();
