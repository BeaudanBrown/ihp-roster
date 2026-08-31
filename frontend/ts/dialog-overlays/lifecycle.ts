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
