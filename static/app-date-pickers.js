"use strict";
(() => {
  // frontend/ts/generated/contracts.ts
  var pageReadyEvent = "bepis:page-ready";

  // frontend/ts/shared/lifecycle.ts
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
      altFormat: "d.m.y, H:i"
    } : {
      altFormat: "d.m.y"
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
  function rootFromPageEvent(event) {
    const detail = event instanceof CustomEvent ? event.detail : void 0;
    return detail?.target instanceof Element || detail?.target instanceof Document ? detail.target : document;
  }
  function handleSwap(event) {
    const detail = event instanceof CustomEvent ? event.detail : void 0;
    if (detail?.target instanceof HTMLElement) {
      initWithin(detail.target);
    }
  }
  function enableDatePickers() {
    if (typeof window === "undefined") return;
    onAppPageReady((event) => {
      initWithin(rootFromPageEvent(event));
    });
    document.addEventListener("htmx:afterSwap", handleSwap);
    document.addEventListener("htmx:oobAfterSwap", handleSwap);
  }
  enableDatePickers();
})();
