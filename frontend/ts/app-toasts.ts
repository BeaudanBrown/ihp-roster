import {
    pageReadyEvent,
    parseToastConfig,
    toastCloseDomAttr,
    toastConfigDomAttr,
    toastMountDomAttr,
    toastOverlayMountDomId,
    type ToastConfig,
} from "./generated/contracts";

// Shared toast host for redirects and HTMX-triggered transient messages.
const hostId = toastOverlayMountDomId;
const toastMountSelector = `[${toastMountDomAttr}]`;
const toastCloseSelector = `[${toastCloseDomAttr}]`;
const initializedToasts = new WeakSet<HTMLElement>();

export function parseToastConfiguration(raw: string): ToastConfig {
    const config = parseToastConfig(JSON.parse(raw));
    if (config.autoHideMs < 0) {
        throw new Error("ToastConfig autoHideMs must not be negative");
    }
    return config;
}

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
    if (initializedToasts.has(toastEl)) return;
    initializedToasts.add(toastEl);

    const rawConfig = toastEl.getAttribute(toastConfigDomAttr);
    let config: ToastConfig;
    try {
        if (rawConfig === null) throw new Error(`Missing ${toastConfigDomAttr}`);
        config = parseToastConfiguration(rawConfig);
    } catch (error) {
        console.error?.("Invalid generated toast configuration", {
            code: "invalid-toast-config",
            message: error instanceof Error ? error.message : String(error),
        });
        return;
    }
    if (config.autoHideMs > 0) {
        window.setTimeout(() => {
            dismissToast(toastEl);
        }, config.autoHideMs);
    }
}

function initHostToasts(): void {
    const hostEl = getHost();
    if (!(hostEl instanceof HTMLElement)) return;
    hostEl.querySelectorAll<HTMLElement>(toastMountSelector).forEach(initToast);
}

function enableToastOverlayHost(): void {
    if (typeof window === "undefined") return;

    document.addEventListener("click", (event) => {
        if (!(event.target instanceof Element)) return;
        const closeEl = event.target.closest<HTMLElement>(toastCloseSelector);
        if (!(closeEl instanceof HTMLElement)) return;

        const toastEl = closeEl.closest<HTMLElement>(toastMountSelector);
        if (toastEl instanceof HTMLElement) {
            dismissToast(toastEl);
        }
    });

    document.addEventListener(pageReadyEvent, initHostToasts);
}

enableToastOverlayHost();
