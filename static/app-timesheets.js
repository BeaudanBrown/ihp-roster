"use strict";
(() => {
  // frontend/ts/generated/contracts.ts
  var pageReadyEvent = "bepis:page-ready";
  var dialogOverlayMountDomId = "dialog-overlay-mount";
  var timesheetWeekShellDomToken = "timesheet-week-shell";

  // frontend/ts/shared/lifecycle.ts
  function onAppPageReady(handler) {
    if (typeof document === "undefined") return;
    document.addEventListener(pageReadyEvent, handler);
  }

  // frontend/ts/app-timesheets.ts
  var dialogMountId = dialogOverlayMountDomId;
  var entryLinkSelector = `#${timesheetWeekShellDomToken} .timesheet-entry-card-link`;
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
    onAppPageReady(() => {
      ensureMountObserver();
      handlePossibleDialogClose();
    });
  }
  blurPointerOpenedTimesheetEntryAfterDialogClose();
})();
