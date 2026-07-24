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
  function isHorizontalSnapMode(value) {
    return typeof value === "string" && ["equal-groups", "nearest-item"].includes(value);
  }
  function isHorizontalSnapConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["snapMode", "itemSelector", "groupCount", "groupProperty", "groupScopeSelector"], ["snapMode", "itemSelector", "groupCount", "groupProperty", "groupScopeSelector"]) && isHorizontalSnapMode(value["snapMode"]) && (value["itemSelector"] === null || typeof value["itemSelector"] === "string") && (value["groupCount"] === null || typeof value["groupCount"] === "number" && Number.isInteger(value["groupCount"])) && (value["groupProperty"] === null || typeof value["groupProperty"] === "string") && (value["groupScopeSelector"] === null || typeof value["groupScopeSelector"] === "string");
  }
  function parseHorizontalSnapConfig(value) {
    if (isHorizontalSnapConfig(value)) return value;
    throw new Error("Invalid HorizontalSnapConfig");
  }
  function isHorizontalDragConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["ignoreSelector"], ["ignoreSelector"]) && (value["ignoreSelector"] === null || typeof value["ignoreSelector"] === "string");
  }
  function parseHorizontalDragConfig(value) {
    if (isHorizontalDragConfig(value)) return value;
    throw new Error("Invalid HorizontalDragConfig");
  }
  var horizontalScrollSnapDomAttr = "data-bepis-horizontal-scroll-snap";
  var horizontalSnapConfigDomAttr = "data-bepis-horizontal-snap-config";
  var horizontalScrollDragDomAttr = "data-bepis-horizontal-scroll-drag";
  var horizontalDragConfigDomAttr = "data-bepis-horizontal-drag-config";

  // frontend/ts/horizontal-scroll/configuration.ts
  function parseHorizontalSnapConfiguration(raw) {
    const config = parseHorizontalSnapConfig(JSON.parse(raw));
    if (config.snapMode === "nearest-item") {
      if (config.itemSelector === null || config.itemSelector.trim() === "") {
        throw new Error("nearest-item snap requires itemSelector");
      }
      if (config.groupCount !== null || config.groupProperty !== null || config.groupScopeSelector !== null) {
        throw new Error("nearest-item snap must not declare equal-group configuration");
      }
      return config;
    }
    if (config.itemSelector !== null) {
      throw new Error("equal-groups snap must not declare itemSelector");
    }
    const hasCount = config.groupCount !== null;
    const hasProperty = config.groupProperty !== null || config.groupScopeSelector !== null;
    if (hasCount === hasProperty) {
      throw new Error("equal-groups snap requires exactly one group source");
    }
    if (config.groupCount !== null && config.groupCount <= 0) {
      throw new Error("equal-groups groupCount must be positive");
    }
    if (hasProperty && (config.groupProperty === null || config.groupProperty.trim() === "" || config.groupScopeSelector === null || config.groupScopeSelector.trim() === "")) {
      throw new Error("equal-groups CSS source must include property and scope selector");
    }
    return config;
  }
  function parseHorizontalDragConfiguration(raw) {
    const config = parseHorizontalDragConfig(JSON.parse(raw));
    if (config.ignoreSelector !== null && config.ignoreSelector.trim() === "") {
      throw new Error("horizontal drag ignoreSelector must not be empty");
    }
    return config;
  }

  // frontend/ts/horizontal-scroll/math.ts
  function parsePositiveIntegerForHorizontalScroll(value) {
    const parsed = Number.parseInt(value || "", 10);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
  }
  function clampHorizontalScrollLeft(scrollLeft, scrollWidth, clientWidth) {
    const maxScrollLeft = Math.max(0, scrollWidth - clientWidth);
    return Math.min(Math.max(0, scrollLeft), maxScrollLeft);
  }

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

  // frontend/ts/app-horizontal-scroll.ts
  var snapSelector = `[${horizontalScrollSnapDomAttr}]`;
  var dragSelector = `[${horizontalScrollDragDomAttr}]`;
  var capabilitySelector = `${snapSelector}, ${dragSelector}`;
  var phoneMediaQuery = "(max-width: 575.98px)";
  var interactiveIgnoreSelector = [
    "a",
    "button",
    "input",
    "select",
    "textarea",
    "label",
    '[role="button"]',
    '[role="link"]'
  ].join(", ");
  var snapDraggingClass = "is-horizontal-snap-dragging";
  var dragDraggingClass = "is-horizontal-dragging";
  var snapDebounceMs = 120;
  var snapTolerancePx = 1;
  var dragThresholdPx = 6;
  var clickSuppressionMs = 250;
  function defaultDiagnosticReporter(diagnostic) {
    console.error?.("Invalid generated horizontal-scroll configuration", diagnostic);
  }
  function readConfig(element, attribute, parse) {
    const raw = element.getAttribute(attribute);
    if (raw === null) throw new Error(`Missing ${attribute}`);
    return parse(raw);
  }
  function validateLocalSelectors(element, snapConfig, dragConfig) {
    if (snapConfig?.itemSelector !== null && snapConfig?.itemSelector !== void 0) {
      element.querySelector(snapConfig.itemSelector);
    }
    if (snapConfig?.groupScopeSelector !== null && snapConfig?.groupScopeSelector !== void 0) {
      element.closest(snapConfig.groupScopeSelector);
    }
    if (dragConfig?.ignoreSelector !== null && dragConfig?.ignoreSelector !== void 0) {
      element.matches(dragConfig.ignoreSelector);
    }
  }
  var HorizontalScrollControl = class {
    constructor(element, snapConfig, dragConfig) {
      this.abortController = new AbortController();
      this.pointerAbortController = null;
      this.timerId = null;
      this.generation = 0;
      this.pointerIds = /* @__PURE__ */ new Set();
      this.touchIds = /* @__PURE__ */ new Set();
      this.activeDrag = null;
      this.suppressClickUntil = 0;
      this.onPointerDown = (event) => {
        if (this.snappingIsEnabled()) {
          this.bumpGeneration();
          this.pointerIds.add(event.pointerId);
          this.element.classList.add(snapDraggingClass);
          this.startPointerTracking();
        }
        if (this.dragConfig === null || event.pointerType !== "mouse" || event.button !== 0 || this.targetIsIgnored(event.target) || this.element.scrollWidth <= this.element.clientWidth) return;
        this.activeDrag = {
          pointerId: event.pointerId,
          startX: event.clientX,
          startScrollLeft: this.element.scrollLeft,
          isDragging: false,
          didDrag: false
        };
        this.startPointerTracking();
        try {
          this.element.setPointerCapture(event.pointerId);
        } catch (_error) {
        }
      };
      this.onPointerMove = (event) => {
        const drag = this.activeDrag;
        if (drag === null || event.pointerId !== drag.pointerId) return;
        const deltaX = event.clientX - drag.startX;
        if (!drag.isDragging && Math.abs(deltaX) < dragThresholdPx) return;
        if (!drag.isDragging) {
          drag.isDragging = true;
          drag.didDrag = true;
          this.element.classList.add(dragDraggingClass);
          if (this.snappingIsEnabled()) this.element.classList.add(snapDraggingClass);
          window.getSelection?.()?.removeAllRanges();
        }
        this.element.scrollLeft = drag.startScrollLeft - deltaX;
        event.preventDefault();
      };
      this.onPointerUp = (event) => this.finishPointer(event, true);
      this.onPointerCancel = (event) => this.finishPointer(event, false);
      this.onTouchStart = (event) => {
        if (!this.snappingIsEnabled()) return;
        this.bumpGeneration();
        for (const touch of Array.from(event.changedTouches)) this.touchIds.add(touch.identifier);
        this.element.classList.add(snapDraggingClass);
      };
      this.onTouchEnd = (event) => {
        for (const touch of Array.from(event.changedTouches)) this.touchIds.delete(touch.identifier);
        this.releaseSnapInput();
      };
      this.onWheel = () => {
        if (this.snappingIsEnabled()) this.bumpGeneration();
      };
      this.onScroll = () => this.scheduleSnap();
      this.onClick = (event) => {
        if (Date.now() <= this.suppressClickUntil) {
          event.preventDefault();
          event.stopPropagation();
        }
      };
      this.element = element;
      this.snapConfig = snapConfig;
      this.dragConfig = dragConfig;
      this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
      const options = { capture: true, signal: this.abortController.signal };
      element.addEventListener("pointerdown", this.onPointerDown, options);
      element.addEventListener("touchstart", this.onTouchStart, options);
      element.addEventListener("touchend", this.onTouchEnd, options);
      element.addEventListener("touchcancel", this.onTouchEnd, options);
      element.addEventListener("wheel", this.onWheel, options);
      element.addEventListener("scroll", this.onScroll, options);
      element.addEventListener("click", this.onClick, options);
    }
    dispose() {
      this.abortController.abort();
      this.stopPointerTracking();
      this.clearTimer();
      this.pointerIds.clear();
      this.touchIds.clear();
      this.activeDrag = null;
      this.element.classList.remove(snapDraggingClass, dragDraggingClass);
    }
    snappingIsEnabled() {
      return this.snapConfig !== null && window.matchMedia(phoneMediaQuery).matches;
    }
    clearTimer() {
      if (this.timerId !== null) {
        window.clearTimeout(this.timerId);
        this.timerId = null;
      }
    }
    bumpGeneration() {
      this.generation += 1;
      this.clearTimer();
    }
    inputIsActive() {
      return this.pointerIds.size > 0 || this.touchIds.size > 0 || this.activeDrag?.isDragging === true;
    }
    scheduleSnap() {
      if (!this.snappingIsEnabled() || this.inputIsActive()) return;
      this.clearTimer();
      const scheduledGeneration = this.generation;
      this.timerId = window.setTimeout(() => {
        this.timerId = null;
        if (this.generation !== scheduledGeneration || this.inputIsActive()) return;
        this.snap();
      }, snapDebounceMs);
    }
    releaseSnapInput() {
      if (this.inputIsActive()) return;
      this.element.classList.remove(snapDraggingClass);
      this.scheduleSnap();
    }
    smoothScrollTo(scrollLeft) {
      const targetLeft = clampHorizontalScrollLeft(
        scrollLeft,
        this.element.scrollWidth,
        this.element.clientWidth
      );
      if (Math.abs(this.element.scrollLeft - targetLeft) <= snapTolerancePx) return;
      this.element.scrollTo({
        left: targetLeft,
        behavior: this.reducedMotion.matches ? "auto" : "smooth"
      });
    }
    groupCount() {
      if (this.snapConfig === null || this.snapConfig.snapMode !== "equal-groups") return 1;
      if (this.snapConfig.groupCount !== null) return this.snapConfig.groupCount;
      if (this.snapConfig.groupProperty === null || this.snapConfig.groupScopeSelector === null) return 1;
      const styleSource = this.element.closest(this.snapConfig.groupScopeSelector);
      if (!(styleSource instanceof Element)) return 1;
      return parsePositiveIntegerForHorizontalScroll(
        window.getComputedStyle(styleSource).getPropertyValue(this.snapConfig.groupProperty)
      ) ?? 1;
    }
    snap() {
      if (this.snapConfig === null) return;
      if (this.snapConfig.snapMode === "equal-groups") {
        const groupWidth = this.element.scrollWidth / this.groupCount();
        if (Number.isFinite(groupWidth) && groupWidth > 0) {
          this.smoothScrollTo(Math.round(this.element.scrollLeft / groupWidth) * groupWidth);
        }
        return;
      }
      if (this.snapConfig.itemSelector === null) return;
      const items = Array.from(this.element.querySelectorAll(this.snapConfig.itemSelector)).filter((item) => item instanceof HTMLElement);
      const containerRect = this.element.getBoundingClientRect();
      const center = containerRect.left + containerRect.width / 2;
      let nearest = null;
      for (const item of items) {
        const rect2 = item.getBoundingClientRect();
        const distance = Math.abs(rect2.left + rect2.width / 2 - center);
        if (nearest === null || distance < nearest.distance) nearest = { element: item, distance };
      }
      if (nearest === null) return;
      const rect = nearest.element.getBoundingClientRect();
      this.smoothScrollTo(this.element.scrollLeft + rect.left + rect.width / 2 - center);
    }
    targetIsIgnored(target) {
      if (!(target instanceof Element)) return false;
      const custom = this.dragConfig?.ignoreSelector;
      const selector = custom === null || custom === void 0 ? interactiveIgnoreSelector : `${interactiveIgnoreSelector}, ${custom}`;
      return target.closest(selector) !== null;
    }
    startPointerTracking() {
      if (this.pointerAbortController !== null) return;
      this.pointerAbortController = new AbortController();
      const options = { capture: true, signal: this.pointerAbortController.signal };
      document.addEventListener("pointermove", this.onPointerMove, options);
      document.addEventListener("pointerup", this.onPointerUp, options);
      document.addEventListener("pointercancel", this.onPointerCancel, options);
    }
    stopPointerTracking() {
      this.pointerAbortController?.abort();
      this.pointerAbortController = null;
    }
    finishPointer(event, scheduleAfterRelease) {
      const drag = this.activeDrag;
      const ownsDrag = drag !== null && event.pointerId === drag.pointerId;
      if (!ownsDrag && !this.pointerIds.has(event.pointerId)) return;
      if (drag !== null && ownsDrag) {
        this.activeDrag = null;
        this.element.classList.remove(dragDraggingClass);
        try {
          this.element.releasePointerCapture(drag.pointerId);
        } catch (_error) {
        }
        if (drag.didDrag) {
          this.suppressClickUntil = Date.now() + clickSuppressionMs;
          window.setTimeout(() => {
            if (Date.now() >= this.suppressClickUntil) this.suppressClickUntil = 0;
          }, clickSuppressionMs);
        }
      }
      this.pointerIds.delete(event.pointerId);
      if (this.pointerIds.size === 0 && this.activeDrag === null) {
        this.stopPointerTracking();
      }
      if (scheduleAfterRelease || !ownsDrag) this.releaseSnapInput();
      else if (!this.inputIsActive()) this.element.classList.remove(snapDraggingClass);
    }
  };
  var controls = /* @__PURE__ */ new Map();
  function controlFor(element, report) {
    const existing = controls.get(element);
    if (existing !== void 0) return existing;
    let snapConfig = null;
    if (element.hasAttribute(horizontalScrollSnapDomAttr)) {
      try {
        snapConfig = readConfig(element, horizontalSnapConfigDomAttr, parseHorizontalSnapConfiguration);
      } catch (error) {
        report({
          code: "invalid-snap-config",
          elementId: element.id,
          message: error instanceof Error ? error.message : String(error)
        });
        return null;
      }
    }
    let dragConfig = null;
    if (element.hasAttribute(horizontalScrollDragDomAttr)) {
      try {
        dragConfig = readConfig(element, horizontalDragConfigDomAttr, parseHorizontalDragConfiguration);
      } catch (error) {
        report({
          code: "invalid-drag-config",
          elementId: element.id,
          message: error instanceof Error ? error.message : String(error)
        });
        return null;
      }
    }
    try {
      validateLocalSelectors(element, snapConfig, null);
    } catch (error) {
      report({
        code: "invalid-snap-config",
        elementId: element.id,
        message: error instanceof Error ? error.message : String(error)
      });
      return null;
    }
    try {
      validateLocalSelectors(element, null, dragConfig);
    } catch (error) {
      report({
        code: "invalid-drag-config",
        elementId: element.id,
        message: error instanceof Error ? error.message : String(error)
      });
      return null;
    }
    const control = new HorizontalScrollControl(element, snapConfig, dragConfig);
    controls.set(element, control);
    return control;
  }
  function capabilityElementsWithin(target) {
    const root = rootFromTarget(target);
    const elements = Array.from(root.querySelectorAll(capabilitySelector)).filter((element) => element instanceof HTMLElement);
    if (root instanceof HTMLElement && root.matches(capabilitySelector)) elements.unshift(root);
    return elements;
  }
  function initializeHorizontalScroll(target, report = defaultDiagnosticReporter) {
    for (const element of capabilityElementsWithin(target)) controlFor(element, report);
  }
  function disposeHorizontalScroll(target) {
    const root = rootFromTarget(target);
    for (const [element, control] of controls) {
      if (element === root || root instanceof Node && root.contains(element)) {
        control.dispose();
        controls.delete(element);
      }
    }
  }
  function enableHorizontalScroll() {
    if (typeof window === "undefined") return;
    onAppPageReady((event) => initializeHorizontalScroll(detailTarget(event, "target")));
    onHtmxLoad((event) => initializeHorizontalScroll(detailTarget(event, "elt")));
    document.addEventListener("htmx:beforeCleanupElement", (event) => {
      const cleanupRoot = detailTarget(event, "elt");
      if (cleanupRoot instanceof Element) disposeHorizontalScroll(cleanupRoot);
    });
    if (document.readyState !== "loading") initializeHorizontalScroll(document.body);
  }
  enableHorizontalScroll();
})();
