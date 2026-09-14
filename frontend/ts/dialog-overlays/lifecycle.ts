import { dialogDismissedEvent, dialogPointerDismissBlurDomAttr } from "../generated/contracts";
import { closestHTMLElement } from "../shared/dom";

// Listeners belong to the document lifetime, not to replaceable dialog mounts.
const pointerDismissOwners = new WeakSet<Document>();

export function installPointerDismissFocusCleanup(owner: Document): void {
    const view = owner.defaultView;
    if (view === null || pointerDismissOwners.has(owner)) return;
    pointerDismissOwners.add(owner);
    let pointerOpenedLauncher: HTMLElement | null = null;

    owner.addEventListener("pointerdown", (event) => {
        const launcher = closestHTMLElement(event.target, `[${dialogPointerDismissBlurDomAttr}]`);
        if (launcher !== null) pointerOpenedLauncher = launcher;
    }, true);
    owner.addEventListener("keydown", () => { pointerOpenedLauncher = null; }, true);
    owner.addEventListener(dialogDismissedEvent, (event) => {
        const detail = dialogDismissedDetail(event);
        if (detail === null || detail.replacement !== null || pointerOpenedLauncher === null) return;
        view.requestAnimationFrame(() => {
            // Read at frame time: an intervening keydown must cancel the blur.
            const launcher = pointerOpenedLauncher;
            pointerOpenedLauncher = null;
            if (launcher !== null && owner.contains(launcher) && owner.activeElement === launcher) launcher.blur();
        });
    });
}

export interface DialogDismissedDetail {
    dialog: Element;
    replacement: Element | null;
}

export interface DialogDismissalLifecycle {
    dismiss(dialog: Element, eventOwner: EventTarget, replacement?: Element | null): boolean;
    reconcile(mount: Element, activeDialog: Element | null): boolean;
}

export function dialogDismissedDetail(event: Event): DialogDismissedDetail | null {
    if (!(event instanceof CustomEvent)) return null;
    const detail = event.detail;
    if (detail === null || typeof detail !== "object") return null;
    const candidate = detail as Partial<DialogDismissedDetail>;
    if (!(candidate.dialog instanceof Element)) return null;
    if (candidate.replacement !== undefined && candidate.replacement !== null && !(candidate.replacement instanceof Element)) return null;
    return { dialog: candidate.dialog, replacement: candidate.replacement ?? null };
}

export function createDialogDismissalLifecycle(eventName: string): DialogDismissalLifecycle {
    const activeDialogs = new WeakMap<Element, Element | null>();
    const dismissedDialogs = new WeakSet<Element>();

    function dismiss(dialog: Element, eventOwner: EventTarget, replacement: Element | null = null): boolean {
        if (dismissedDialogs.has(dialog)) return false;
        dismissedDialogs.add(dialog);
        eventOwner.dispatchEvent(new CustomEvent<DialogDismissedDetail>(eventName, {
            bubbles: true,
            detail: { dialog, replacement },
        }));
        return true;
    }

    function reconcile(mount: Element, activeDialog: Element | null): boolean {
        const previousDialog = activeDialogs.get(mount) ?? null;
        activeDialogs.set(mount, activeDialog);
        if (previousDialog === null || previousDialog === activeDialog) return false;
        return dismiss(previousDialog, mount, activeDialog);
    }

    return { dismiss, reconcile };
}
