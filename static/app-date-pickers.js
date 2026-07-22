"use strict";
(() => {
  // frontend/ts/generated/contracts.ts
  var pageReadyEvent = "bepis:page-ready";

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
  function onAppPageReady(handler) {
    if (typeof document === "undefined") return;
    document.addEventListener(pageReadyEvent, handler);
  }

  // frontend/ts/app-date-pickers.ts
  var initializedKey = "appDatePickerInitialized";
  function datePickerConfigFor(inputType) {
    return inputType === "datetime-local" ? {
      enableTime: true,
      time_24hr: true,
      dateFormat: "Z",
      altInput: true,
      altFormat: "d/m/Y, H:i"
    } : {
      dateFormat: "Y-m-d",
      altInput: true,
      altFormat: "d/m/Y"
    };
  }
  function initInput(inputEl) {
    if (typeof window.flatpickr !== "function") return;
    if (inputEl.dataset[initializedKey] === "true") return;
    if (inputEl._flatpickr !== void 0) {
      inputEl.dataset[initializedKey] = "true";
      return;
    }
    window.flatpickr(inputEl, datePickerConfigFor(inputEl.type));
    inputEl.dataset[initializedKey] = "true";
  }
  function initWithin(root) {
    if (root instanceof HTMLInputElement && (root.type === "date" || root.type === "datetime-local")) {
      initInput(root);
    }
    root.querySelectorAll("input[type='date'], input[type='datetime-local']").forEach(initInput);
  }
  function handleSwap(event) {
    initWithin(detailRoot(event, "target"));
  }
  function enableDatePickers() {
    if (typeof window === "undefined") return;
    onAppPageReady((event) => {
      initWithin(detailRoot(event, "target"));
    });
    document.addEventListener("htmx:afterSwap", handleSwap);
    document.addEventListener("htmx:oobAfterSwap", handleSwap);
  }
  enableDatePickers();
})();
