import { dialogOverlayMountDomId, timesheetWeekShellDomToken } from "./generated/contracts";
import { onAppPageReady } from "./shared/lifecycle";

const dialogMountId = dialogOverlayMountDomId;
const entryLinkSelector = `#${timesheetWeekShellDomToken} .timesheet-entry-card-link`;
let pointerOpenedEntryLink: HTMLElement | null = null;
let mountObserver: MutationObserver | null = null;

function getDialogMount(): HTMLElement | null {
    return document.getElementById(dialogMountId);
}

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

function isDialogMountEmpty(): boolean {
    const mountEl = getDialogMount();
    return mountEl instanceof HTMLElement && mountEl.children.length === 0;
}

function handlePossibleDialogClose(): void {
    if (pointerOpenedEntryLink === null) return;
    if (!isDialogMountEmpty()) return;

    window.requestAnimationFrame(blurTrackedEntryLinkIfFocused);
}

function ensureMountObserver(): void {
    if (mountObserver !== null) return;
    if (typeof window.MutationObserver !== "function") return;

    const mountEl = getDialogMount();
    if (!(mountEl instanceof HTMLElement)) return;

    mountObserver = new MutationObserver(handlePossibleDialogClose);
    mountObserver.observe(mountEl, { childList: true });
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

    document.addEventListener("DOMContentLoaded", ensureMountObserver);
    onAppPageReady(() => {
        ensureMountObserver();
        handlePossibleDialogClose();
    });
}

blurPointerOpenedTimesheetEntryAfterDialogClose();
