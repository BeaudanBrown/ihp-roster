import { dialogDismissedEvent, timesheetWeekShellDomToken } from "./generated/contracts";
import { dialogDismissedDetail } from "./dialog-overlays/lifecycle";

const entryLinkSelector = `#${timesheetWeekShellDomToken} .timesheet-entry-card-link`;
let pointerOpenedEntryLink: HTMLElement | null = null;

function clearTrackedEntryLink(): void {
    pointerOpenedEntryLink = null;
}

function blurTrackedEntryLinkIfFocused(): void {
    const linkEl = pointerOpenedEntryLink;
    clearTrackedEntryLink();

    if (!(linkEl instanceof HTMLElement)) return;
    if (!document.contains(linkEl)) return;
    if (document.activeElement === linkEl) {
        linkEl.blur();
    }
}

function blurPointerOpenedTimesheetEntryAfterDialogClose(): void {
    if (typeof window === "undefined") return;

    document.addEventListener("pointerdown", (event) => {
        if (!(event.target instanceof Element)) return;

        const linkEl = event.target.closest<HTMLElement>(entryLinkSelector);
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
