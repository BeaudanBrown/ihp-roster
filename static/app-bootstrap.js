"use strict";
(() => {
  // frontend/ts/generated/contracts.ts
  var pageReadyEvent = "bepis:page-ready";

  // frontend/ts/shared/dom.ts
  function isDocument(value) {
    return typeof Document !== "undefined" && value instanceof Document;
  }
  function isHTMLElement(value) {
    return typeof HTMLElement !== "undefined" && value instanceof HTMLElement;
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

  // frontend/ts/app-bootstrap.ts
  var appPageReadyEventName = pageReadyEvent;
  function detailRecord(detail) {
    return detail !== null && typeof detail === "object" ? detail : {};
  }
  function pageReadyDetailFrom(detail) {
    const record = detailRecord(detail);
    const source = record.source;
    return {
      source: typeof source === "string" && source !== "" ? source : "unknown",
      isFullPage: Boolean(record.isFullPage)
    };
  }
  (function enableAppPageLifecycle() {
    if (typeof window === "undefined") return;
    const pageReadyEventName = appPageReadyEventName;
    function normalizeTarget(target) {
      if (isHTMLElement(target)) return target;
      if (isDocument(target)) return document.body;
      return document.body;
    }
    function dispatchPageReady(detail) {
      const target = normalizeTarget(detailRecord(detail).target);
      const event = new CustomEvent(pageReadyEventName, {
        detail: {
          target,
          ...pageReadyDetailFrom(detail)
        }
      });
      document.dispatchEvent(event);
    }
    window.appPageLifecycle = {
      eventName: pageReadyEventName,
      dispatchPageReady
    };
    document.addEventListener(pageReadyEventName, function(event) {
      const target = normalizeTarget(detailTarget(event, "target"));
      window.htmx?.process?.(target);
    });
    document.addEventListener("DOMContentLoaded", function() {
      dispatchPageReady({
        source: "dom-content-loaded",
        target: document.body,
        isFullPage: true
      });
    });
    document.addEventListener("htmx:afterSwap", function(event) {
      dispatchPageReady({
        source: "htmx-after-swap",
        target: detailTarget(event, "target"),
        isFullPage: false
      });
    });
    document.addEventListener("htmx:oobAfterSwap", function(event) {
      dispatchPageReady({
        source: "htmx-oob-after-swap",
        target: detailTarget(event, "target"),
        isFullPage: false
      });
    });
    if (document.readyState !== "loading") {
      dispatchPageReady({
        source: "document-ready",
        target: document.body,
        isFullPage: true
      });
    }
  })();
  (function enableTrackedTimers() {
    if (typeof window === "undefined") return;
    if (!Array.isArray(window.allIntervals)) {
      window.allIntervals = [];
    }
    if (!Array.isArray(window.allTimeouts)) {
      window.allTimeouts = [];
    }
    if (typeof window.unsafeSetInterval !== "function") {
      window.unsafeSetInterval = window.setInterval.bind(window);
    }
    if (typeof window.unsafeSetTimeout !== "function") {
      window.unsafeSetTimeout = window.setTimeout.bind(window);
    }
    if (window.setInterval !== trackedSetInterval) {
      window.setInterval = trackedSetInterval;
    }
    if (window.setTimeout !== trackedSetTimeout) {
      window.setTimeout = trackedSetTimeout;
    }
    if (typeof window.clearAllIntervals !== "function") {
      window.clearAllIntervals = function clearAllIntervals() {
        for (const intervalId of window.allIntervals ?? []) {
          window.clearInterval(intervalId);
        }
        window.allIntervals = [];
      };
    }
    if (typeof window.clearAllTimeouts !== "function") {
      window.clearAllTimeouts = function clearAllTimeouts() {
        for (const timeoutId of window.allTimeouts ?? []) {
          window.clearTimeout(timeoutId);
        }
        window.allTimeouts = [];
      };
    }
    function trackedSetInterval(...args) {
      const intervalId = window.unsafeSetInterval?.(...args) ?? window.setInterval(...args);
      window.allIntervals?.push(intervalId);
      return intervalId;
    }
    function trackedSetTimeout(...args) {
      const timeoutId = window.unsafeSetTimeout?.(...args) ?? window.setTimeout(...args);
      window.allTimeouts?.push(timeoutId);
      return timeoutId;
    }
  })();
})();
