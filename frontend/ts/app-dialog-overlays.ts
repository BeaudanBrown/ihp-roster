import {
    dialogBackdropDomAttr,
    dialogBlockingDomAttr,
    dialogCloseDomAttr,
    dialogDismissedEvent,
    dialogFocusRegionDomAttr,
    dialogKeyboardDomAttr,
    dialogMountDomAttr,
    dialogOverlayMountDomId,
    dialogSubmitConfigDomAttr,
    dialogSubmitDomAttr,
    navigationLoadingConfigDomAttr,
    navigationLoadingDomAttr,
    pageReadyEvent,
    parseDialogSubmitConfig,
    parseNavigationLoadingConfig,
    type DialogSubmitConfig,
    type NavigationLoadingConfig,
} from "./generated/contracts";
import { createDialogDismissalLifecycle, installPointerDismissFocusCleanup } from "./dialog-overlays/lifecycle";
import { closestHTMLElement, isHTMLElement } from "./shared/dom";
import { detailRoot, detailTarget } from "./shared/lifecycle";

const dialogMountSelector = `[${dialogMountDomAttr}]`;
const dialogKeyboardSelector = `[${dialogKeyboardDomAttr}]`;
const dialogFocusRegionSelector = `[${dialogFocusRegionDomAttr}]`;
const dialogBackdropSelector = `[${dialogBackdropDomAttr}]`;
const dialogCloseSelector = `[${dialogCloseDomAttr}]`;
const navigationLoadingSelector = `form[${navigationLoadingDomAttr}]`;
const originalSubmitHtml = new WeakMap<HTMLButtonElement, string>();
interface DialogLoadingState {
    contentChildren: Array<{ element: HTMLElement; hidden: boolean }>;
    loadingPanel: HTMLElement;
    previousAriaBusy: string | null;
    wasBlocking: boolean;
}
const dialogLoadingStates = new WeakMap<HTMLElement, DialogLoadingState>();
const checkboxControlledHiddenOptions = new WeakMap<HTMLInputElement, HTMLOptionElement[]>();

export function syncCheckboxControlledHiddenSelectOptions(checkbox: HTMLInputElement): void {
    if (checkbox.type !== "checkbox") return;
    const controlledId = checkbox.getAttribute("aria-controls")?.trim();
    if (controlledId === undefined || controlledId.length === 0 || /\s/.test(controlledId)) return;
    const controlled = checkbox.ownerDocument.getElementById(controlledId);
    if (!(controlled instanceof HTMLSelectElement)) return;

    let hiddenOptions = checkboxControlledHiddenOptions.get(checkbox);
    if (hiddenOptions === undefined) {
        hiddenOptions = Array.from(controlled.options).filter((option) => option.hidden);
        checkboxControlledHiddenOptions.set(checkbox, hiddenOptions);
    }

    hiddenOptions.forEach((option) => {
        option.hidden = !checkbox.checked;
    });
    if (!checkbox.checked && hiddenOptions.some((option) => option.selected)) {
        controlled.value = "";
    }
    checkbox.setAttribute("aria-expanded", checkbox.checked ? "true" : "false");
}

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

export function parseNavigationLoadingConfiguration(raw: string): NavigationLoadingConfig {
    const config = parseNavigationLoadingConfig(JSON.parse(raw));
    if (config.loadingTitle.trim().length === 0) {
        throw new Error("NavigationLoadingConfig loadingTitle must not be empty");
    }
    if (config.loadingMessage.trim().length === 0) {
        throw new Error("NavigationLoadingConfig loadingMessage must not be empty");
    }
    return config;
}

function navigationLoadingConfiguration(form: HTMLFormElement): NavigationLoadingConfig | null {
    const rawConfig = form.getAttribute(navigationLoadingConfigDomAttr);
    try {
        if (rawConfig === null) throw new Error(`Missing ${navigationLoadingConfigDomAttr}`);
        return parseNavigationLoadingConfiguration(rawConfig);
    } catch (error) {
        console.error?.("Invalid generated navigation loading configuration", {
            code: "invalid-navigation-loading-config",
            message: error instanceof Error ? error.message : String(error),
        });
        return null;
    }
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

function showDialogSubmitLoading(dialog: HTMLElement, config: DialogSubmitConfig): void {
    if (dialogLoadingStates.has(dialog)) return;
    const content = dialog.querySelector(":scope > .modal-dialog > .modal-content");
    if (!(content instanceof HTMLElement)) return;

    const contentChildren = Array.from(content.children)
        .filter(isHTMLElement)
        .map((element) => ({ element, hidden: element.hidden }));
    contentChildren.forEach(({ element }) => {
        element.hidden = true;
    });

    const loadingPanel = document.createElement("div");
    loadingPanel.className = "modal-body d-flex align-items-center justify-content-center gap-3 py-5";
    loadingPanel.setAttribute("role", "status");
    loadingPanel.setAttribute("aria-live", "polite");
    const spinner = document.createElement("span");
    spinner.className = "spinner-border text-primary";
    spinner.setAttribute("aria-hidden", "true");
    const label = document.createElement("span");
    label.className = "fw-semibold";
    label.textContent = config.loadingLabel;
    loadingPanel.append(spinner, label);
    content.append(loadingPanel);

    const state: DialogLoadingState = {
        contentChildren,
        loadingPanel,
        previousAriaBusy: dialog.getAttribute("aria-busy"),
        wasBlocking: dialog.hasAttribute(dialogBlockingDomAttr),
    };
    dialogLoadingStates.set(dialog, state);
    dialog.setAttribute("aria-busy", "true");
    dialog.setAttribute(dialogBlockingDomAttr, "true");
    dialog.focus({ preventScroll: true });
}

function restoreDialogSubmitLoading(dialog: HTMLElement): void {
    const state = dialogLoadingStates.get(dialog);
    if (state === undefined) return;

    state.loadingPanel.remove();
    state.contentChildren.forEach(({ element, hidden }) => {
        element.hidden = hidden;
    });
    if (state.previousAriaBusy === null) {
        dialog.removeAttribute("aria-busy");
    } else {
        dialog.setAttribute("aria-busy", state.previousAriaBusy);
    }
    if (!state.wasBlocking) dialog.removeAttribute(dialogBlockingDomAttr);
    dialogLoadingStates.delete(dialog);
}

// Shared workflow dialog mount for HTMX-driven form overlays.
(function enableDialogOverlayMount() {
    if (typeof window === "undefined") return;

    const mountId = dialogOverlayMountDomId;
    const dismissalLifecycle = createDialogDismissalLifecycle(dialogDismissedEvent);
    installPointerDismissFocusCleanup(document);
    const blockingBackgroundInertStates = new Map<HTMLElement, boolean>();
    let blockingDialogReturnFocus: HTMLElement | null = null;

    function getMount(): HTMLElement | null {
        const mountEl = document.getElementById(mountId);
        return isHTMLElement(mountEl) ? mountEl : null;
    }

    function getActiveDialog(): HTMLElement | null {
        const dialogs = Array.from(document.querySelectorAll(dialogMountSelector)).filter(isHTMLElement);
        return dialogs.length === 0 ? null : dialogs[dialogs.length - 1];
    }

    function getMountedDialog(mountEl: HTMLElement): HTMLElement | null {
        const dialogs = Array.from(mountEl.querySelectorAll(dialogMountSelector)).filter(isHTMLElement);
        return dialogs.length === 0 ? null : dialogs[dialogs.length - 1];
    }

    function reconcileDialogDismissal(mountEl: HTMLElement): void {
        dismissalLifecycle.reconcile(mountEl, getMountedDialog(mountEl));
    }

    function keyboardFocusRegion(dialog: HTMLElement): HTMLElement | null {
        if (!dialog.matches(dialogKeyboardSelector)) return null;
        const regions = Array.from(dialog.querySelectorAll(dialogFocusRegionSelector));
        return regions.length === 1 && regions[0] instanceof HTMLElement ? regions[0] : null;
    }

    function focusableDialogControls(region: HTMLElement): HTMLElement[] {
        const selector = [
            "input:not([type='hidden']):not([disabled])",
            "select:not([disabled])",
            "textarea:not([disabled])",
            "button:not([disabled])",
            "a[href]",
            "[contenteditable='true']",
            "[tabindex]:not([tabindex='-1'])",
        ].join(",");

        return Array.from(region.querySelectorAll(selector)).filter((element): element is HTMLElement => {
            if (!(element instanceof HTMLElement)) return false;
            if (element.hidden || element.closest("[hidden], [inert]") !== null) return false;
            return element.tabIndex >= 0;
        });
    }

    function focusKeyboardDialog(dialog: HTMLElement): void {
        const region = keyboardFocusRegion(dialog);
        if (region === null) return;
        const controls = focusableDialogControls(region);
        const firstInvalid = controls.find((control) => control.getAttribute("aria-invalid") === "true");
        const autofocus = controls.find((control) => control.hasAttribute("autofocus"));
        (firstInvalid ?? autofocus ?? controls[0] ?? dialog).focus({ preventScroll: true });
    }

    function initializeKeyboardDialogs(root: ParentNode): void {
        if (root instanceof HTMLElement && root.matches(dialogKeyboardSelector)) focusKeyboardDialog(root);
        root.querySelectorAll(dialogKeyboardSelector).forEach((dialog) => {
            if (dialog instanceof HTMLElement) focusKeyboardDialog(dialog);
        });
    }

    function hasVisibleBootstrapModal(): boolean {
        return Boolean(document.querySelector(`.modal.show:not(${dialogMountSelector})`));
    }

    function syncDialogState(): void {
        const hasDialog = getActiveDialog() !== null;
        const shouldLockBody = hasDialog || hasVisibleBootstrapModal();

        document.body.classList.toggle("modal-open", shouldLockBody);
        document.body.style.overflow = shouldLockBody ? "hidden" : "";
    }

    function showNavigationLoadingDialog(config: NavigationLoadingConfig): void {
        const mountEl = getMount();
        if (mountEl === null) return;

        const dialogEl = document.createElement("div");
        dialogEl.className = "modal fade show d-block";
        dialogEl.setAttribute(dialogMountDomAttr, "true");
        dialogEl.setAttribute(dialogBlockingDomAttr, "true");
        dialogEl.setAttribute("tabindex", "-1");
        dialogEl.setAttribute("role", "dialog");
        dialogEl.setAttribute("aria-modal", "true");
        dialogEl.setAttribute("aria-label", config.loadingTitle);

        const modalDialog = document.createElement("div");
        modalDialog.className = "modal-dialog modal-dialog-centered";
        modalDialog.setAttribute("role", "document");
        const content = document.createElement("div");
        content.className = "modal-content shadow";
        const body = document.createElement("div");
        body.className = "modal-body d-flex align-items-center gap-3 py-4";
        body.setAttribute("role", "status");
        body.setAttribute("aria-live", "polite");
        const spinner = document.createElement("span");
        spinner.className = "spinner-border text-primary";
        spinner.setAttribute("aria-hidden", "true");
        const copy = document.createElement("div");
        const title = document.createElement("h2");
        title.className = "h5 mb-1";
        title.textContent = config.loadingTitle;
        const message = document.createElement("p");
        message.className = "mb-0 app-muted";
        message.textContent = config.loadingMessage;
        copy.append(title, message);
        body.append(spinner, copy);
        content.append(body);
        modalDialog.append(content);
        dialogEl.append(modalDialog);

        const backdrop = document.createElement("div");
        backdrop.className = "modal-backdrop fade show";
        backdrop.setAttribute(dialogBackdropDomAttr, "true");
        blockingDialogReturnFocus = isHTMLElement(document.activeElement) ? document.activeElement : null;
        const replacedDialog = getMountedDialog(mountEl);
        if (replacedDialog !== null) dismissalLifecycle.dismiss(replacedDialog, mountEl, dialogEl);
        mountEl.replaceChildren(dialogEl, backdrop);
        reconcileDialogDismissal(mountEl);
        setBlockingBackgroundInert(mountEl, true);
        syncDialogState();
        dialogEl.focus();
    }

    function setBlockingBackgroundInert(mountEl: HTMLElement, inert: boolean): void {
        Array.from(document.body.children).forEach((element) => {
            if (!(element instanceof HTMLElement) || element === mountEl) return;
            if (inert) {
                if (!blockingBackgroundInertStates.has(element)) {
                    blockingBackgroundInertStates.set(element, element.inert);
                }
                element.inert = true;
                return;
            }
            const previous = blockingBackgroundInertStates.get(element);
            if (previous !== undefined) element.inert = previous;
            blockingBackgroundInertStates.delete(element);
        });
    }

    function clearDialog(dialogEl: HTMLElement): void {
        const mountEl = getMount();
        const eventOwner = mountEl !== null && mountEl.contains(dialogEl) ? mountEl : dialogEl;
        dismissalLifecycle.dismiss(dialogEl, eventOwner);

        const wasBlocking = dialogEl.hasAttribute(dialogBlockingDomAttr);
        const inheritedBlockingState = blockingBackgroundInertStates.size > 0;
        if ((wasBlocking || inheritedBlockingState) && mountEl !== null) setBlockingBackgroundInert(mountEl, false);
        const returnFocus = wasBlocking || inheritedBlockingState ? blockingDialogReturnFocus : null;
        if (wasBlocking || inheritedBlockingState) blockingDialogReturnFocus = null;
        if (mountEl !== null && mountEl.contains(dialogEl)) {
            mountEl.innerHTML = "";
            reconcileDialogDismissal(mountEl);
            syncDialogState();
            if (returnFocus?.isConnected) returnFocus.focus();
            return;
        }

        const localOwner = dialogEl.parentElement;
        dialogEl.remove();
        if (localOwner !== null) {
            Array.from(localOwner.children).forEach((element) => {
                if (element.matches(dialogBackdropSelector)) element.remove();
            });
        }
        syncDialogState();
        if (returnFocus?.isConnected) returnFocus.focus();
    }

    function releaseInheritedBlockingStateWhenDialogAbsent(mountEl: HTMLElement): void {
        if (getActiveDialog() !== null || blockingBackgroundInertStates.size === 0) return;

        setBlockingBackgroundInert(mountEl, false);
        const returnFocus = blockingDialogReturnFocus;
        blockingDialogReturnFocus = null;
        if (returnFocus?.isConnected) returnFocus.focus();
    }

    document.addEventListener("click", function (event) {
        const closeEl = closestHTMLElement(event.target, dialogCloseSelector);
        const closeDialog = closeEl?.closest(dialogMountSelector);
        if (closeEl !== null && isHTMLElement(closeDialog)) {
            event.preventDefault();
            clearDialog(closeDialog);
            return;
        }

        const backdropEl = closestHTMLElement(event.target, dialogBackdropSelector);
        const backdropDialog = backdropEl?.parentElement?.querySelector(dialogMountSelector);
        if (backdropEl !== null && isHTMLElement(backdropDialog)) {
            event.preventDefault();
            if (backdropDialog.hasAttribute(dialogBlockingDomAttr)) return;
            clearDialog(backdropDialog);
            return;
        }

        // The full-screen dialog shell sits above the backdrop, so background clicks
        // often land on the shell instead of the separate backdrop node.
        const activeDialog = getActiveDialog();
        if (activeDialog !== null && event.target === activeDialog) {
            event.preventDefault();
            if (activeDialog.hasAttribute(dialogBlockingDomAttr)) return;
            clearDialog(activeDialog);
        }
    });

    document.addEventListener("keydown", function (event) {
        const activeDialog = getActiveDialog();
        if (activeDialog === null) return;
        if (event.key === "Tab" && activeDialog.hasAttribute(dialogBlockingDomAttr)) {
            event.preventDefault();
            activeDialog.focus();
            return;
        }

        const focusRegion = keyboardFocusRegion(activeDialog);
        if (event.key === "Tab" && focusRegion !== null) {
            const controls = focusableDialogControls(focusRegion);
            event.preventDefault();
            if (controls.length === 0) {
                activeDialog.focus();
                return;
            }
            const currentIndex = controls.indexOf(document.activeElement as HTMLElement);
            const nextIndex = event.shiftKey
                ? (currentIndex <= 0 ? controls.length - 1 : currentIndex - 1)
                : (currentIndex < 0 || currentIndex === controls.length - 1 ? 0 : currentIndex + 1);
            controls[nextIndex]?.focus();
            return;
        }

        if (event.key === "Enter" && focusRegion !== null && !event.isComposing && !event.ctrlKey && !event.metaKey && !event.altKey) {
            const target = event.target;
            if (target instanceof HTMLTextAreaElement || (target instanceof HTMLElement && target.isContentEditable)) return;
            const submitter = activeDialog.querySelector(`[${dialogSubmitDomAttr}]`);
            if (submitter instanceof HTMLButtonElement && !submitter.disabled && submitter.form !== null) {
                event.preventDefault();
                submitter.form.requestSubmit(submitter);
            }
            return;
        }

        if (event.key !== "Escape") return;

        event.preventDefault();
        if (!activeDialog.hasAttribute(dialogBlockingDomAttr)) clearDialog(activeDialog);
    });

    document.addEventListener("change", function (event) {
        const target = event.target;
        if (target instanceof HTMLInputElement) syncCheckboxControlledHiddenSelectOptions(target);
    });

    document.addEventListener("submit", function (event) {
        if (event.defaultPrevented) return;
        const submittedForm = event.target;
        if (submittedForm instanceof HTMLFormElement && submittedForm.matches(navigationLoadingSelector)) {
            const navigationConfig = navigationLoadingConfiguration(submittedForm);
            if (navigationConfig !== null) showNavigationLoadingDialog(navigationConfig);
        }

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
        showDialogSubmitLoading(activeDialog, config);
    }, true);

    document.addEventListener("htmx:afterRequest", function (event) {
        const activeDialog = getActiveDialog();
        if (activeDialog === null) return;
        const elt = detailTarget(event, "elt");
        if (!isHTMLElement(elt)) return;
        if (!activeDialog.contains(elt)) return;

        restoreDialogSubmitLoading(activeDialog);
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
        const target = detailRoot(event, "target");
        if (!isHTMLElement(target)) return;
        if (target.id !== mountId) return;

        initializeKeyboardDialogs(target);
        reconcileDialogDismissal(target);
        releaseInheritedBlockingStateWhenDialogAbsent(target);

        syncDialogState();
    });

    document.addEventListener("htmx:oobAfterSwap", function (event) {
        const target = detailRoot(event, "target");
        if (!isHTMLElement(target)) return;
        if (target.id !== mountId) return;

        initializeKeyboardDialogs(target);
        reconcileDialogDismissal(target);
        releaseInheritedBlockingStateWhenDialogAbsent(target);
        syncDialogState();
    });

    window.addEventListener("pageshow", function (event) {
        if (!event.persisted) return;
        const activeDialog = getActiveDialog();
        if (activeDialog !== null && activeDialog.hasAttribute(dialogBlockingDomAttr)) {
            clearDialog(activeDialog);
        }
    });
    document.addEventListener("shown.bs.modal", syncDialogState);
    document.addEventListener("hidden.bs.modal", syncDialogState);
    document.addEventListener(pageReadyEvent, (event) => {
        const mountEl = getMount();
        if (mountEl !== null) reconcileDialogDismissal(mountEl);
        syncDialogState();
        const target = detailTarget(event, "target");
        if (target instanceof HTMLElement || target instanceof Document) initializeKeyboardDialogs(target);
    });
})();
