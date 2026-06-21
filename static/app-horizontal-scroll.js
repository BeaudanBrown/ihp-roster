"use strict";
(() => {
  // frontend/ts/app-horizontal-scroll.ts
  function parsePositiveIntegerForHorizontalScroll(value) {
    const parsed = Number.parseInt(value || "", 10);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
  }
  function clampHorizontalScrollLeft(scrollLeft, scrollWidth, clientWidth) {
    const maxScrollLeft = Math.max(0, scrollWidth - clientWidth);
    return Math.min(Math.max(0, scrollLeft), maxScrollLeft);
  }
  (function enableHorizontalScroll() {
    if (typeof window === "undefined") return;
    const snapContainerSelector = "[data-horizontal-snap]";
    const dragContainerSelector = "[data-horizontal-drag-scroll]";
    const defaultPhoneMediaQuery = "(max-width: 575.98px)";
    const defaultInteractiveIgnoreSelector = [
      "a",
      "button",
      "input",
      "select",
      "textarea",
      "label",
      '[role="button"]',
      '[role="link"]'
    ].join(", ");
    const reducedMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
    const snapDebounceMs = 120;
    const snapTolerancePx = 1;
    const defaultDragThresholdPx = 6;
    const defaultClickSuppressionMs = 250;
    const snapStates = /* @__PURE__ */ new WeakMap();
    const mediaQueries = /* @__PURE__ */ new Map();
    const pointerSnapContainers = /* @__PURE__ */ new Map();
    const touchSnapContainers = /* @__PURE__ */ new Map();
    let activeDrag = null;
    function mediaQueryFor(containerEl) {
      const media = containerEl.dataset.horizontalSnapMedia || "phone";
      const query = media === "phone" ? defaultPhoneMediaQuery : media;
      if (!mediaQueries.has(query)) {
        mediaQueries.set(query, window.matchMedia(query));
      }
      return mediaQueries.get(query);
    }
    function snappingIsEnabled(containerEl) {
      const mediaQuery = mediaQueryFor(containerEl);
      return !mediaQuery || mediaQuery.matches;
    }
    function isSupportedSnapMode(containerEl) {
      return containerEl.dataset.horizontalSnap === "equal-groups" || containerEl.dataset.horizontalSnap === "nearest-item";
    }
    function isSupportedDragMode(containerEl) {
      return containerEl.dataset.horizontalDragScroll === "mouse";
    }
    function findSnapContainer(target) {
      if (!(target instanceof Element)) return null;
      const containerEl = target.closest(snapContainerSelector);
      return containerEl instanceof HTMLElement && isSupportedSnapMode(containerEl) ? containerEl : null;
    }
    function findDragContainer(target) {
      if (!(target instanceof Element)) return null;
      const containerEl = target.closest(dragContainerSelector);
      return containerEl instanceof HTMLElement && isSupportedDragMode(containerEl) ? containerEl : null;
    }
    function snapStateFor(containerEl) {
      let state = snapStates.get(containerEl);
      if (!state) {
        state = {
          generation: 0,
          timerId: null,
          pointerIds: /* @__PURE__ */ new Set(),
          touchIds: /* @__PURE__ */ new Set(),
          pendingSnap: false,
          programmaticSnapGeneration: null
        };
        snapStates.set(containerEl, state);
      }
      return state;
    }
    function clearSnapTimer(containerEl) {
      const state = snapStateFor(containerEl);
      if (state.timerId !== null) {
        window.clearTimeout(state.timerId);
        state.timerId = null;
      }
    }
    function bumpSnapGeneration(containerEl) {
      const state = snapStateFor(containerEl);
      state.generation += 1;
      state.programmaticSnapGeneration = null;
      state.pendingSnap = false;
      clearSnapTimer(containerEl);
      return state.generation;
    }
    function snapInputIsActive(containerEl) {
      const state = snapStateFor(containerEl);
      return state.pointerIds.size > 0 || state.touchIds.size > 0 || Boolean(activeDrag && activeDrag.containerEl === containerEl && activeDrag.isDragging);
    }
    function setSnapDragging(containerEl) {
      containerEl.setAttribute("data-horizontal-snap-dragging", "true");
    }
    function clearSnapDragging(containerEl) {
      containerEl.removeAttribute("data-horizontal-snap-dragging");
    }
    function clampScrollLeft(containerEl, scrollLeft) {
      const maxScrollLeft = Math.max(0, containerEl.scrollWidth - containerEl.clientWidth);
      return Math.min(Math.max(0, scrollLeft), maxScrollLeft);
    }
    function smoothScrollTo(containerEl, scrollLeft) {
      const targetLeft = clampScrollLeft(containerEl, scrollLeft);
      if (Math.abs(containerEl.scrollLeft - targetLeft) <= snapTolerancePx) return;
      const state = snapStateFor(containerEl);
      state.programmaticSnapGeneration = state.generation;
      containerEl.scrollTo({
        left: targetLeft,
        behavior: reducedMotionQuery.matches ? "auto" : "smooth"
      });
    }
    function parsePositiveInteger(value) {
      const parsed = Number.parseInt(value || "", 10);
      return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
    }
    function readGroupCount(containerEl) {
      const explicitCount = parsePositiveInteger(containerEl.dataset.horizontalSnapGroupCount);
      if (explicitCount) return explicitCount;
      const groupVar = containerEl.dataset.horizontalSnapGroupVar;
      if (groupVar) {
        const styleSource = containerEl.closest(containerEl.dataset.horizontalSnapGroupVarScope || "[style]") || containerEl;
        const varCount = parsePositiveInteger(window.getComputedStyle(styleSource).getPropertyValue(groupVar));
        if (varCount) return varCount;
      }
      return 1;
    }
    function snapEqualGroups(containerEl) {
      const groupCount = readGroupCount(containerEl);
      const groupWidth = containerEl.scrollWidth / groupCount;
      if (!Number.isFinite(groupWidth) || groupWidth <= 0) return;
      smoothScrollTo(containerEl, Math.round(containerEl.scrollLeft / groupWidth) * groupWidth);
    }
    function snapNearestItem(containerEl) {
      const itemSelector = containerEl.dataset.horizontalSnapItemSelector;
      if (!itemSelector) return;
      const items = Array.from(containerEl.querySelectorAll(itemSelector)).filter(function(itemEl) {
        return itemEl instanceof HTMLElement;
      });
      if (items.length === 0) return;
      const containerRect = containerEl.getBoundingClientRect();
      const containerCenter = containerRect.left + containerRect.width / 2;
      const nearestItem = items.reduce(function(nearest, itemEl) {
        const itemRect2 = itemEl.getBoundingClientRect();
        const itemCenter = itemRect2.left + itemRect2.width / 2;
        const distance = Math.abs(itemCenter - containerCenter);
        if (!nearest || distance < nearest.distance) {
          return { itemEl, distance };
        }
        return nearest;
      }, null);
      if (!nearestItem) return;
      const itemRect = nearestItem.itemEl.getBoundingClientRect();
      const targetLeft = containerEl.scrollLeft + (itemRect.left + itemRect.width / 2) - containerCenter;
      smoothScrollTo(containerEl, targetLeft);
    }
    function snapContainer(containerEl) {
      if (!snappingIsEnabled(containerEl)) return;
      if (containerEl.dataset.horizontalSnap === "equal-groups") {
        snapEqualGroups(containerEl);
      } else if (containerEl.dataset.horizontalSnap === "nearest-item") {
        snapNearestItem(containerEl);
      }
    }
    function scheduleSnap(containerEl) {
      if (!snappingIsEnabled(containerEl)) return;
      const state = snapStateFor(containerEl);
      if (snapInputIsActive(containerEl)) {
        state.pendingSnap = true;
        return;
      }
      clearSnapTimer(containerEl);
      const scheduledGeneration = state.generation;
      state.timerId = window.setTimeout(function() {
        state.timerId = null;
        if (state.generation !== scheduledGeneration || snapInputIsActive(containerEl)) {
          state.pendingSnap = true;
          return;
        }
        snapContainer(containerEl);
      }, snapDebounceMs);
    }
    function releaseSnapContainer(containerEl) {
      const state = snapStateFor(containerEl);
      if (snapInputIsActive(containerEl)) return;
      clearSnapDragging(containerEl);
      state.pendingSnap = false;
      scheduleSnap(containerEl);
    }
    function pointerStartForSnap(event) {
      const containerEl = findSnapContainer(event.target);
      if (!(containerEl instanceof HTMLElement) || !snappingIsEnabled(containerEl)) return;
      const state = snapStateFor(containerEl);
      bumpSnapGeneration(containerEl);
      state.pointerIds.add(event.pointerId);
      pointerSnapContainers.set(event.pointerId, containerEl);
      setSnapDragging(containerEl);
    }
    function pointerEndForSnap(event) {
      const containerEl = pointerSnapContainers.get(event.pointerId);
      if (!(containerEl instanceof HTMLElement)) return;
      pointerSnapContainers.delete(event.pointerId);
      const state = snapStateFor(containerEl);
      state.pointerIds.delete(event.pointerId);
      releaseSnapContainer(containerEl);
    }
    function touchStartForSnap(event) {
      const containerEl = findSnapContainer(event.target);
      if (!(containerEl instanceof HTMLElement) || !snappingIsEnabled(containerEl)) return;
      const state = snapStateFor(containerEl);
      bumpSnapGeneration(containerEl);
      Array.from(event.changedTouches).forEach(function(touch) {
        state.touchIds.add(touch.identifier);
        touchSnapContainers.set(touch.identifier, containerEl);
      });
      setSnapDragging(containerEl);
    }
    function touchEndForSnap(event) {
      const affectedContainers = /* @__PURE__ */ new Set();
      Array.from(event.changedTouches).forEach(function(touch) {
        const containerEl = touchSnapContainers.get(touch.identifier);
        if (!(containerEl instanceof HTMLElement)) return;
        touchSnapContainers.delete(touch.identifier);
        snapStateFor(containerEl).touchIds.delete(touch.identifier);
        affectedContainers.add(containerEl);
      });
      affectedContainers.forEach(releaseSnapContainer);
    }
    function parseNonNegativeInteger(value, fallback) {
      const parsed = Number.parseInt(value || "", 10);
      return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
    }
    function dragThresholdFor(containerEl) {
      return parseNonNegativeInteger(containerEl.dataset.horizontalDragScrollThreshold, defaultDragThresholdPx);
    }
    function clickSuppressionMsFor(containerEl) {
      return parseNonNegativeInteger(containerEl.dataset.horizontalDragScrollClickSuppressionMs, defaultClickSuppressionMs);
    }
    function dragIgnoreSelectorFor(containerEl) {
      const customSelector = containerEl.dataset.horizontalDragScrollIgnoreSelector;
      return customSelector ? defaultInteractiveIgnoreSelector + ", " + customSelector : defaultInteractiveIgnoreSelector;
    }
    function targetIsIgnoredForDrag(containerEl, target) {
      if (!(target instanceof Element)) return false;
      const selector = dragIgnoreSelectorFor(containerEl);
      return Boolean(target.closest(selector));
    }
    function setDragDragging(containerEl) {
      containerEl.setAttribute("data-horizontal-dragging", "true");
    }
    function clearDragDragging(containerEl) {
      containerEl.removeAttribute("data-horizontal-dragging");
    }
    function suppressNextClick(containerEl) {
      const until = Date.now() + clickSuppressionMsFor(containerEl);
      containerEl.dataset.horizontalSuppressClickUntil = String(until);
      window.setTimeout(function() {
        if (containerEl.dataset.horizontalSuppressClickUntil === String(until)) {
          delete containerEl.dataset.horizontalSuppressClickUntil;
        }
      }, clickSuppressionMsFor(containerEl));
    }
    function pointerStartForDrag(event) {
      if (event.pointerType !== "mouse" || event.button !== 0) return;
      const containerEl = findDragContainer(event.target);
      if (!(containerEl instanceof HTMLElement)) return;
      if (targetIsIgnoredForDrag(containerEl, event.target)) return;
      if (containerEl.scrollWidth <= containerEl.clientWidth) return;
      if (activeDrag) {
        finishDrag(false);
      }
      activeDrag = {
        containerEl,
        pointerId: event.pointerId,
        startX: event.clientX,
        startScrollLeft: containerEl.scrollLeft,
        threshold: dragThresholdFor(containerEl),
        isDragging: false,
        didDrag: false
      };
      if (isSupportedSnapMode(containerEl) && snappingIsEnabled(containerEl)) {
        const state = snapStateFor(containerEl);
        bumpSnapGeneration(containerEl);
        state.pointerIds.add(event.pointerId);
        pointerSnapContainers.set(event.pointerId, containerEl);
        setSnapDragging(containerEl);
      }
      try {
        containerEl.setPointerCapture(event.pointerId);
      } catch (_error) {
      }
    }
    function startActualDrag() {
      if (!activeDrag || activeDrag.isDragging) return;
      activeDrag.isDragging = true;
      activeDrag.didDrag = true;
      setDragDragging(activeDrag.containerEl);
      if (isSupportedSnapMode(activeDrag.containerEl) && snappingIsEnabled(activeDrag.containerEl)) {
        setSnapDragging(activeDrag.containerEl);
      }
      const selection = window.getSelection && window.getSelection();
      if (selection) selection.removeAllRanges();
    }
    function pointerMoveForDrag(event) {
      if (!activeDrag || event.pointerId !== activeDrag.pointerId) return;
      const deltaX = event.clientX - activeDrag.startX;
      if (!activeDrag.isDragging && Math.abs(deltaX) < activeDrag.threshold) return;
      startActualDrag();
      activeDrag.containerEl.scrollLeft = activeDrag.startScrollLeft - deltaX;
      event.preventDefault();
    }
    function finishDrag(scheduleAfterRelease) {
      if (!activeDrag) return;
      const drag = activeDrag;
      activeDrag = null;
      clearDragDragging(drag.containerEl);
      try {
        drag.containerEl.releasePointerCapture(drag.pointerId);
      } catch (_error) {
      }
      if (drag.didDrag) {
        suppressNextClick(drag.containerEl);
      }
      if (isSupportedSnapMode(drag.containerEl) && snappingIsEnabled(drag.containerEl)) {
        const state = snapStateFor(drag.containerEl);
        state.pointerIds.delete(drag.pointerId);
        pointerSnapContainers.delete(drag.pointerId);
        if (!snapInputIsActive(drag.containerEl)) {
          clearSnapDragging(drag.containerEl);
          if (scheduleAfterRelease) scheduleSnap(drag.containerEl);
        }
      }
    }
    function clickForDrag(event) {
      const containerEl = findDragContainer(event.target);
      if (!(containerEl instanceof HTMLElement)) return;
      const suppressUntil = Number.parseInt(containerEl.dataset.horizontalSuppressClickUntil || "", 10);
      if (Number.isFinite(suppressUntil) && Date.now() <= suppressUntil) {
        event.preventDefault();
        event.stopPropagation();
      }
    }
    document.addEventListener("pointerdown", function(event) {
      pointerStartForSnap(event);
      pointerStartForDrag(event);
    }, true);
    document.addEventListener("pointermove", pointerMoveForDrag, true);
    document.addEventListener("pointerup", function(event) {
      if (activeDrag && event.pointerId === activeDrag.pointerId) {
        finishDrag(true);
        return;
      }
      pointerEndForSnap(event);
    }, true);
    document.addEventListener("pointercancel", function(event) {
      if (activeDrag && event.pointerId === activeDrag.pointerId) {
        finishDrag(false);
        return;
      }
      pointerEndForSnap(event);
    }, true);
    document.addEventListener("touchstart", touchStartForSnap, true);
    document.addEventListener("touchend", touchEndForSnap, true);
    document.addEventListener("touchcancel", touchEndForSnap, true);
    document.addEventListener("wheel", function(event) {
      const containerEl = findSnapContainer(event.target);
      if (!(containerEl instanceof HTMLElement) || !snappingIsEnabled(containerEl)) return;
      bumpSnapGeneration(containerEl);
    }, true);
    document.addEventListener("scroll", function(event) {
      if (!(event.target instanceof HTMLElement)) return;
      if (!event.target.matches(snapContainerSelector) || !isSupportedSnapMode(event.target)) return;
      scheduleSnap(event.target);
    }, true);
    document.addEventListener("click", clickForDrag, true);
  })();
})();
