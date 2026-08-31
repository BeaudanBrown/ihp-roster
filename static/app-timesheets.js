"use strict";
(() => {
  // frontend/ts/generated/contracts.ts
  var dialogDismissedEvent = "bepis:dialog-dismissed";
  var timesheetWeekShellDomToken = "timesheet-week-shell";

  // frontend/ts/dialog-overlays/lifecycle.ts
  function dialogDismissedDetail(event) {
    if (!(event instanceof CustomEvent)) return null;
    const detail = event.detail;
    if (detail === null || typeof detail !== "object") return null;
    const candidate = detail;
    if (!(candidate.dialog instanceof Element)) return null;
    if (candidate.replacement !== void 0 && candidate.replacement !== null && !(candidate.replacement instanceof Element)) return null;
    return { dialog: candidate.dialog, replacement: candidate.replacement ?? null };
  }

  // frontend/ts/app-timesheets.ts
  var entryLinkSelector = `#${timesheetWeekShellDomToken} .timesheet-entry-card-link`;
  var pointerOpenedEntryLink = null;
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
    document.addEventListener(dialogDismissedEvent, (event) => {
      const detail = dialogDismissedDetail(event);
      if (detail === null || detail.replacement !== null || pointerOpenedEntryLink === null) return;
      window.requestAnimationFrame(blurTrackedEntryLinkIfFocused);
    });
  }
  blurPointerOpenedTimesheetEntryAfterDialogClose();
})();
