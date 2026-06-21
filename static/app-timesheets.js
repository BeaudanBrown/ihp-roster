"use strict";
(() => {
  // frontend/ts/app-timesheets.ts
  function syncBreakToggle(checkboxEl) {
    const targetSelector = checkboxEl.dataset.breakTarget;
    if (targetSelector === void 0 || targetSelector === "") return;
    const targetEl = document.querySelector(targetSelector);
    if (targetEl === null) return;
    const isEnabled = checkboxEl.checked;
    targetEl.querySelectorAll(".js-time-picker-input, .js-time-picker-trigger, .js-time-picker-step-down, .js-time-picker-step-up").forEach((element) => {
      element.disabled = !isEnabled;
    });
    document.dispatchEvent(new CustomEvent("time-picker:sync", { detail: { target: targetEl } }));
  }
  function syncAllBreakTogglesWithin(root) {
    root.querySelectorAll('[data-break-toggle="true"]').forEach((checkboxEl) => {
      syncBreakToggle(checkboxEl);
    });
  }
  function detailTarget(event, key) {
    return event instanceof CustomEvent && event.detail !== null && typeof event.detail === "object" ? event.detail[key] : void 0;
  }
  function enableBreakTimeToggle() {
    if (typeof window === "undefined") return;
    document.addEventListener("change", (event) => {
      if (!(event.target instanceof Element)) return;
      const checkboxEl = event.target.closest('[data-break-toggle="true"]');
      if (checkboxEl === null) return;
      syncBreakToggle(checkboxEl);
    });
    document.addEventListener("app:page-ready", (event) => {
      const target = detailTarget(event, "target");
      if (target instanceof Element || target instanceof Document) {
        syncAllBreakTogglesWithin(target);
      }
    });
  }
  enableBreakTimeToggle();
  var dialogMountId = "dialog-overlay-mount";
  var entryLinkSelector = ".timesheet-entry-card-link";
  var pointerOpenedEntryLink = null;
  var mountObserver = null;
  function getDialogMount() {
    return document.getElementById(dialogMountId);
  }
  function clearTrackedEntryLink() {
    pointerOpenedEntryLink = null;
  }
  function blurTrackedEntryLinkIfFocused() {
    const linkEl = pointerOpenedEntryLink;
    clearTrackedEntryLink();
    if (!(linkEl instanceof HTMLElement)) return;
    if (!document.contains(linkEl)) return;
    if (document.activeElement === linkEl) {
      linkEl.blur();
    }
  }
  function isDialogMountEmpty() {
    const mountEl = getDialogMount();
    return mountEl instanceof HTMLElement && mountEl.children.length === 0;
  }
  function handlePossibleDialogClose() {
    if (pointerOpenedEntryLink === null) return;
    if (!isDialogMountEmpty()) return;
    window.requestAnimationFrame(blurTrackedEntryLinkIfFocused);
  }
  function ensureMountObserver() {
    if (mountObserver !== null) return;
    if (typeof window.MutationObserver !== "function") return;
    const mountEl = getDialogMount();
    if (!(mountEl instanceof HTMLElement)) return;
    mountObserver = new MutationObserver(handlePossibleDialogClose);
    mountObserver.observe(mountEl, { childList: true });
  }
  function blurPointerOpenedTimesheetEntryAfterDialogClose() {
    if (typeof window === "undefined") return;
    document.addEventListener("pointerdown", (event) => {
      if (!(event.target instanceof Element)) return;
      const linkEl = event.target.closest(entryLinkSelector);
      if (linkEl instanceof HTMLElement) {
        pointerOpenedEntryLink = linkEl;
      }
    }, true);
    document.addEventListener("keydown", clearTrackedEntryLink, true);
    document.addEventListener("DOMContentLoaded", ensureMountObserver);
    document.addEventListener("app:page-ready", () => {
      ensureMountObserver();
      handlePossibleDialogClose();
    });
  }
  blurPointerOpenedTimesheetEntryAfterDialogClose();
})();
