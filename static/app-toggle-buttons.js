"use strict";
(() => {
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
  function rootFromTarget(target, fallback = document) {
    return isDomRoot(target) ? target : fallback;
  }

  // frontend/ts/generated/contracts.ts
  var pageReadyEvent = "bepis:page-ready";

  // frontend/ts/shared/lifecycle.ts
  function eventDetailRecord(event) {
    if (typeof CustomEvent === "undefined" || !(event instanceof CustomEvent)) return null;
    if (event.detail === null || typeof event.detail !== "object") return null;
    return event.detail;
  }
  function detailTarget(event, key) {
    return eventDetailRecord(event)?.[key];
  }
  function onAppPageReady(handler) {
    if (typeof document === "undefined") return;
    document.addEventListener(pageReadyEvent, handler);
  }
  function onHtmxLoad(handler) {
    if (typeof document === "undefined") return;
    document.addEventListener("htmx:load", handler);
  }

  // frontend/ts/app-toggle-buttons.ts
  function syncHiddenInput(input) {
    const hiddenInputId = input.dataset.appToggleHiddenInputId;
    if (hiddenInputId === void 0 || hiddenInputId === "") return;
    const hiddenInput = document.getElementById(hiddenInputId);
    if (!(hiddenInput instanceof HTMLInputElement)) return;
    const checkedValue = input.dataset.appToggleHiddenCheckedValue ?? "true";
    const uncheckedValue = input.dataset.appToggleHiddenUncheckedValue ?? "false";
    hiddenInput.value = input.checked ? checkedValue : uncheckedValue;
  }
  function syncToggleButton(input) {
    const button = input.closest("[data-app-toggle-button]");
    if (button === null) return;
    button.querySelectorAll("[data-app-toggle-label-state]").forEach((label) => {
      const state = label.dataset.appToggleLabelState;
      if (state === "checked") label.hidden = !input.checked;
      if (state === "unchecked") label.hidden = input.checked;
    });
    button.classList.toggle("btn-success", input.checked);
    button.classList.toggle("btn-outline-success", !input.checked);
    button.setAttribute("aria-pressed", input.checked ? "true" : "false");
    if (input.getAttribute("role") === "switch") {
      input.setAttribute("aria-checked", input.checked ? "true" : "false");
    }
    syncHiddenInput(input);
  }
  function initToggleButtons(target) {
    const root = rootFromTarget(target);
    root.querySelectorAll('[data-app-toggle-button-input="true"]').forEach((input) => {
      if (input.dataset.appToggleButtonReady === "true") return;
      input.dataset.appToggleButtonReady = "true";
      input.addEventListener("change", () => {
        syncToggleButton(input);
      });
      syncToggleButton(input);
    });
  }
  function enableAppToggleButtons() {
    if (typeof window === "undefined") return;
    onAppPageReady((event) => {
      initToggleButtons(detailTarget(event, "target"));
    });
    onHtmxLoad((event) => {
      initToggleButtons(detailTarget(event, "elt"));
    });
    if (document.readyState !== "loading") {
      initToggleButtons(document.body);
    }
  }
  enableAppToggleButtons();
})();
