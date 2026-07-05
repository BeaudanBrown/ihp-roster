import { pageReadyEvent, toastOverlayMountDomId } from "./generated/contracts";

// Bottom-right toast host for redirects and HTMX-triggered transient messages.
const hostId = toastOverlayMountDomId;
const initializedKey = "toastInitialized";

function getHost(): HTMLElement | null {
    return document.getElementById(hostId);
}

export function dismissToast(toastEl: HTMLElement): void {
    toastEl.classList.add("app-toast-leaving");
    window.setTimeout(() => {
        if (toastEl.parentNode !== null) {
            toastEl.remove();
        }
    }, 220);
}

function initToast(toastEl: HTMLElement): void {
    if (toastEl.dataset[initializedKey] === "true") return;

    toastEl.dataset[initializedKey] = "true";
    const autoHideMs = Number.parseInt(toastEl.dataset.autoHideMs ?? "0", 10);
    if (autoHideMs > 0) {
        window.setTimeout(() => {
            dismissToast(toastEl);
        }, autoHideMs);
    }
}

function initHostToasts(): void {
    const hostEl = getHost();
    if (!(hostEl instanceof HTMLElement)) return;
    hostEl.querySelectorAll<HTMLElement>('[data-overlay-toast="true"]').forEach(initToast);
}

function enableToastOverlayHost(): void {
    if (typeof window === "undefined") return;

    document.addEventListener("click", (event) => {
        if (!(event.target instanceof Element)) return;
        const closeEl = event.target.closest<HTMLElement>('[data-toast-close="true"]');
        if (!(closeEl instanceof HTMLElement)) return;

        const toastEl = closeEl.closest<HTMLElement>('[data-overlay-toast="true"]');
        if (toastEl instanceof HTMLElement) {
            dismissToast(toastEl);
        }
    });

    document.addEventListener(pageReadyEvent, initHostToasts);
}

enableToastOverlayHost();
