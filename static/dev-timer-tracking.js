"use strict";
(() => {
  // frontend/ts/dev-timer-tracking.ts
  (function enableDevelopmentTimerTracking() {
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
