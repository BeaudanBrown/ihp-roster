import { type DomRoot } from "./shared/dom";
import { detailRoot, onAppPageReady } from "./shared/lifecycle";

// Enable/disable break-time controls based on the "Had break" checkbox.
function syncBreakToggle(checkboxEl: HTMLInputElement): void {
    const targetSelector = checkboxEl.dataset.breakTarget;
    if (targetSelector === undefined || targetSelector === "") return;

    const targetEl = document.querySelector(targetSelector);
    if (targetEl === null) return;

    const isEnabled = checkboxEl.checked;
    targetEl.querySelectorAll<HTMLInputElement | HTMLButtonElement>(".js-time-picker-input, .js-time-picker-trigger, .js-time-picker-step-down, .js-time-picker-step-up").forEach((element) => {
        element.disabled = !isEnabled;
    });
    document.dispatchEvent(new CustomEvent("time-picker:sync", { detail: { target: targetEl } }));
}

function syncAllBreakTogglesWithin(root: DomRoot): void {
    root.querySelectorAll<HTMLInputElement>('[data-break-toggle="true"]').forEach((checkboxEl) => {
        syncBreakToggle(checkboxEl);
    });
}

function enableBreakTimeToggle(): void {
    if (typeof window === "undefined") return;

    document.addEventListener("change", (event) => {
        if (!(event.target instanceof Element)) return;
        const checkboxEl = event.target.closest<HTMLInputElement>('[data-break-toggle="true"]');
        if (checkboxEl === null) return;
        syncBreakToggle(checkboxEl);
    });

    onAppPageReady((event) => {
        syncAllBreakTogglesWithin(detailRoot(event, "target"));
    });
}

enableBreakTimeToggle();

const dialogMountId = "dialog-overlay-mount";
const entryLinkSelector = ".timesheet-entry-card-link";
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
    document.addEventListener("app:page-ready", () => {
        ensureMountObserver();
        handlePossibleDialogClose();
    });
}

blurPointerOpenedTimesheetEntryAfterDialogClose();
