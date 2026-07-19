import {
    dialogAutoSubmitOnceDomAttr,
    dialogBackdropDomAttr,
    dialogCloseDomAttr,
    dialogMountDomAttr,
    dialogOverlayMountDomId,
    dialogSubmitConfigDomAttr,
    dialogSubmitDomAttr,
    pageReadyEvent,
    parseDialogSubmitConfig,
    type DialogSubmitConfig,
} from "./generated/contracts";
import { closestHTMLElement, isHTMLElement } from "./shared/dom";
import { detailTarget } from "./shared/lifecycle";

const dialogMountSelector = `[${dialogMountDomAttr}]`;
const dialogBackdropSelector = `[${dialogBackdropDomAttr}]`;
const dialogCloseSelector = `[${dialogCloseDomAttr}]`;
const autoSubmittedForms = new WeakSet<HTMLFormElement>();
const originalSubmitHtml = new WeakMap<HTMLButtonElement, string>();

export function dialogSubmitLoadingHtml(label: string): string {
    return '<span class="spinner-border spinner-border-sm" aria-hidden="true"></span><span>' + label + "</span>";
}

export function parseDialogSubmitConfiguration(raw: string): DialogSubmitConfig {
    const config = parseDialogSubmitConfig(JSON.parse(raw));
    if (config.loadingLabel.trim().length === 0) {
        throw new Error("DialogSubmitConfig loadingLabel must not be empty");
    }
    return config;
}

function dialogSubmitConfiguration(submitter: HTMLButtonElement): DialogSubmitConfig | null {
    const rawConfig = submitter.getAttribute(dialogSubmitConfigDomAttr);
    try {
        if (rawConfig === null) throw new Error(`Missing ${dialogSubmitConfigDomAttr}`);
        return parseDialogSubmitConfiguration(rawConfig);
    } catch (error) {
        console.error?.("Invalid generated dialog submit configuration", {
            code: "invalid-dialog-submit-config",
            message: error instanceof Error ? error.message : String(error),
        });
        return null;
    }
}

// Shared workflow dialog mount for HTMX-driven form overlays.
(function enableDialogOverlayMount() {
    if (typeof window === "undefined") return;

    const mountId = dialogOverlayMountDomId;
    function getMount(): HTMLElement | null {
        const mountEl = document.getElementById(mountId);
        return isHTMLElement(mountEl) ? mountEl : null;
    }

    function getActiveDialog(): HTMLElement | null {
        const mountEl = getMount();
        if (mountEl === null) return null;
        const dialogEl = mountEl.querySelector(dialogMountSelector);
        return isHTMLElement(dialogEl) ? dialogEl : null;
    }

    function hasVisibleBootstrapModal(): boolean {
        return Boolean(document.querySelector(`.modal.show:not(${dialogMountSelector})`));
    }

    function syncDialogState(): void {
        const dialogEl = getActiveDialog();
        const hasDialog = dialogEl instanceof HTMLElement;
        const shouldLockBody = hasDialog || hasVisibleBootstrapModal();

        document.body.classList.toggle("modal-open", shouldLockBody);
        document.body.style.overflow = shouldLockBody ? "hidden" : "";
    }

    function clearMount(): void {
        const mountEl = getMount();
        if (mountEl === null) return;

        mountEl.innerHTML = "";
        syncDialogState();
    }

    function submitAutoFormsOnce(container: HTMLElement): void {
        container.querySelectorAll(`form[${dialogAutoSubmitOnceDomAttr}]`).forEach(function (form) {
            if (!(form instanceof HTMLFormElement)) return;
            if (autoSubmittedForms.has(form)) return;

            autoSubmittedForms.add(form);
            form.requestSubmit();
        });
    }

    document.addEventListener("click", function (event) {
        const activeDialog = getActiveDialog();
        const closeEl = closestHTMLElement(event.target, dialogCloseSelector);
        if (closeEl !== null && activeDialog !== null) {
            event.preventDefault();
            clearMount();
            return;
        }

        const backdropEl = closestHTMLElement(event.target, dialogBackdropSelector);
        if (backdropEl !== null && activeDialog !== null) {
            event.preventDefault();
            clearMount();
            return;
        }

        // The full-screen dialog shell sits above the backdrop, so background clicks
        // often land on the shell instead of the separate backdrop node.
        if (activeDialog !== null && event.target === activeDialog) {
            event.preventDefault();
            clearMount();
        }
    });

    document.addEventListener("keydown", function (event) {
        if (event.key !== "Escape") return;
        if (getActiveDialog() === null) return;

        event.preventDefault();
        clearMount();
    });

    document.addEventListener("submit", function (event) {
        const activeDialog = getActiveDialog();
        if (activeDialog === null) return;

        const form = event.target;
        if (!(form instanceof HTMLFormElement)) return;

        const submitter = event instanceof SubmitEvent ? event.submitter : null;
        if (!(submitter instanceof HTMLButtonElement)) return;
        if (!submitter.hasAttribute(dialogSubmitDomAttr)) return;
        const config = dialogSubmitConfiguration(submitter);
        if (config === null) return;

        activeDialog.querySelectorAll("button, a.btn").forEach(function (control) {
            if (control instanceof HTMLButtonElement) {
                control.disabled = true;
            } else if (isHTMLElement(control)) {
                control.classList.add("disabled");
                control.setAttribute("aria-disabled", "true");
            }
        });

        if (!originalSubmitHtml.has(submitter)) {
            originalSubmitHtml.set(submitter, submitter.innerHTML);
        }
        submitter.innerHTML = dialogSubmitLoadingHtml(config.loadingLabel);
        submitter.classList.add("d-inline-flex", "align-items-center", "gap-2");
    }, true);

    document.addEventListener("htmx:afterRequest", function (event) {
        const activeDialog = getActiveDialog();
        if (activeDialog === null) return;
        const elt = detailTarget(event, "elt");
        if (!isHTMLElement(elt)) return;
        if (!activeDialog.contains(elt)) return;

        activeDialog.querySelectorAll("button, a.btn").forEach(function (control) {
            if (control instanceof HTMLButtonElement) {
                control.disabled = false;
            } else if (isHTMLElement(control)) {
                control.classList.remove("disabled");
                control.removeAttribute("aria-disabled");
            }
        });

        activeDialog.querySelectorAll(`[${dialogSubmitDomAttr}]`).forEach(function (control) {
            if (!(control instanceof HTMLButtonElement)) return;
            const originalHtml = originalSubmitHtml.get(control);
            if (originalHtml !== undefined) {
                control.innerHTML = originalHtml;
            }
            control.classList.remove("d-inline-flex", "align-items-center", "gap-2");
        });
    });

    document.addEventListener("htmx:afterSwap", function (event) {
        const target = detailTarget(event, "target");
        if (!isHTMLElement(target)) return;
        if (target.id !== mountId) return;

        window.htmx?.process?.(target);
        submitAutoFormsOnce(target);

        syncDialogState();
    });

    document.addEventListener("htmx:oobAfterSwap", function (event) {
        const target = detailTarget(event, "target");
        if (!isHTMLElement(target)) return;
        if (target.id !== mountId) return;

        submitAutoFormsOnce(target);
        syncDialogState();
    });

    document.addEventListener("shown.bs.modal", syncDialogState);
    document.addEventListener("hidden.bs.modal", syncDialogState);
    document.addEventListener(pageReadyEvent, syncDialogState);
})();
