"use strict";
(() => {
  // frontend/ts/app-scrollbars.ts
  var activeClass = "app-scrollbar-active";
  var hideDelayMs = 2e3;
  function scrollElementFromEventTarget(target) {
    if (target === document || target === window || target === document.body || target === document.documentElement) {
      return document.documentElement;
    }
    if (target instanceof Element) return target;
    return document.documentElement;
  }
  function enableAppScrollbars() {
    if (typeof window === "undefined") return;
    const timers = /* @__PURE__ */ new WeakMap();
    function markScrollbarActive(element) {
      element.classList.add(activeClass);
      const existingTimer = timers.get(element);
      if (existingTimer !== void 0) {
        window.clearTimeout(existingTimer);
      }
      const nextTimer = window.setTimeout(() => {
        element.classList.remove(activeClass);
        timers.delete(element);
      }, hideDelayMs);
      timers.set(element, nextTimer);
    }
    document.addEventListener("scroll", (event) => {
      markScrollbarActive(scrollElementFromEventTarget(event.target));
    }, true);
  }
  enableAppScrollbars();
})();
