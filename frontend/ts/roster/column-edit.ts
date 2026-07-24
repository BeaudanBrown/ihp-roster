import {
    isRosterColumnEditingState,
    rosterColumnEditDoneDomAttr,
    rosterColumnEditingDomAttr,
    rosterColumnEditingStates,
    rosterColumnEditorDomAttr,
    rosterColumnEditStartDomAttr,
    type RosterColumnEditingState,
} from "../generated/contracts";
import { detailRoot, detailTarget, onAppPageReady } from "../shared/lifecycle";

export type RosterColumnEditDiagnostic = {
    code: "invalid-editor-role" | "invalid-state" | "invalid-control-role";
    elementId: string | null;
    message: string;
};

export type RosterColumnEditDiagnosticReporter = (diagnostic: RosterColumnEditDiagnostic) => void;

export type RosterColumnEditScheduler = {
    setTimeout: (handler: () => void, delayMs: number) => number;
    clearTimeout: (timerId: number) => void;
};

export type RosterColumnEditController = {
    reconcile: (editor: Element) => boolean;
    start: (target: Element) => boolean;
    finish: (target: Element, activeElement: Element | null) => boolean;
    dispose: (root: Element) => void;
};

const editorSelector = `[${rosterColumnEditorDomAttr}]`;
const startSelector = `[${rosterColumnEditStartDomAttr}]`;
const doneSelector = `[${rosterColumnEditDoneDomAttr}]`;
const finishDelayMs = 350;

function defaultDiagnosticReporter(diagnostic: RosterColumnEditDiagnostic): void {
    console.error?.("Invalid generated roster column-edit boundary", diagnostic);
}

function defaultScheduler(): RosterColumnEditScheduler {
    return {
        setTimeout: (handler, delayMs) => window.setTimeout(handler, delayMs),
        clearTimeout: (timerId) => window.clearTimeout(timerId),
    };
}

function diagnostic(element: Element, code: RosterColumnEditDiagnostic["code"], message: string): RosterColumnEditDiagnostic {
    return { code, elementId: element.id || null, message };
}

function closestEditor(target: Element): Element | null {
    return target.closest(editorSelector);
}

function ownedControls(editor: Element, selector: string): Element[] {
    return Array.from(editor.querySelectorAll(selector)).filter((control) => closestEditor(control) === editor);
}

function stateFor(editor: Element, report: RosterColumnEditDiagnosticReporter): RosterColumnEditingState | null {
    if (editor.getAttribute(rosterColumnEditorDomAttr) !== "true") {
        report(diagnostic(editor, "invalid-editor-role", "Roster column editor role must equal true"));
        return null;
    }
    const state = editor.getAttribute(rosterColumnEditingDomAttr);
    if (!isRosterColumnEditingState(state)) {
        report(diagnostic(editor, "invalid-state", "Roster column-editing state is not declared by the Surface contract"));
        return null;
    }
    return state;
}

export function createRosterColumnEditController(
    report: RosterColumnEditDiagnosticReporter = defaultDiagnosticReporter,
    scheduler: RosterColumnEditScheduler = defaultScheduler(),
): RosterColumnEditController {
    const pendingFinishTimers = new Map<Element, number>();

    function clearPendingFinish(editor: Element): void {
        const timerId = pendingFinishTimers.get(editor);
        if (timerId === undefined) return;
        scheduler.clearTimeout(timerId);
        pendingFinishTimers.delete(editor);
    }

    function reconcile(editor: Element): boolean {
        const state = stateFor(editor, report);
        if (!state) return false;
        const active = state === rosterColumnEditingStates.active;
        const starts = ownedControls(editor, startSelector);
        const doneControls = ownedControls(editor, doneSelector);
        const invalidStarts = starts.filter((start) => start.getAttribute(rosterColumnEditStartDomAttr) !== "true");
        const invalidDoneControls = doneControls.filter((done) => done.getAttribute(rosterColumnEditDoneDomAttr) !== "true");
        invalidStarts.forEach((start) => {
            report(diagnostic(start, "invalid-control-role", "Roster column-edit start role must equal true"));
        });
        invalidDoneControls.forEach((done) => {
            report(diagnostic(done, "invalid-control-role", "Roster column-edit done role must equal true"));
        });
        if (invalidStarts.length > 0 || invalidDoneControls.length > 0) return false;
        starts.forEach((start) => start.setAttribute("aria-pressed", active ? "true" : "false"));
        return true;
    }

    function setState(editor: Element, state: RosterColumnEditingState): boolean {
        if (!stateFor(editor, report)) return false;
        clearPendingFinish(editor);
        editor.setAttribute(rosterColumnEditingDomAttr, state);
        return reconcile(editor);
    }

    function start(target: Element): boolean {
        const startControl = target.closest(startSelector);
        if (!startControl || startControl.getAttribute(rosterColumnEditStartDomAttr) !== "true") return false;
        const editor = closestEditor(startControl);
        if (!editor) return false;
        return setState(editor, rosterColumnEditingStates.active);
    }

    function finish(target: Element, activeElement: Element | null): boolean {
        const doneControl = target.closest(doneSelector);
        if (!doneControl || doneControl.getAttribute(rosterColumnEditDoneDomAttr) !== "true") return false;
        const editor = closestEditor(doneControl);
        if (!editor || !stateFor(editor, report)) return false;

        clearPendingFinish(editor);
        if (activeElement && editor.contains(activeElement)) {
            const blur = (activeElement as HTMLElement).blur;
            if (typeof blur === "function") blur.call(activeElement);
            const timerId = scheduler.setTimeout(() => {
                pendingFinishTimers.delete(editor);
                editor.setAttribute(rosterColumnEditingDomAttr, rosterColumnEditingStates.inactive);
                reconcile(editor);
            }, finishDelayMs);
            pendingFinishTimers.set(editor, timerId);
            return true;
        }

        return setState(editor, rosterColumnEditingStates.inactive);
    }

    function dispose(root: Element): void {
        for (const [editor, timerId] of pendingFinishTimers) {
            if (editor === root || root.contains(editor)) {
                scheduler.clearTimeout(timerId);
                pendingFinishTimers.delete(editor);
            }
        }
    }

    return { reconcile, start, finish, dispose };
}

function editorRootsWithin(root: Document | DocumentFragment | Element): Element[] {
    const editors = Array.from(root.querySelectorAll(editorSelector));
    if (root instanceof Element) {
        if (root.matches(editorSelector)) editors.unshift(root);
        const owner = closestEditor(root);
        if (owner && !editors.includes(owner)) editors.unshift(owner);
    }
    return editors;
}

export function enableRosterColumnEditMode(): void {
    if (typeof window === "undefined") return;
    const controller = createRosterColumnEditController();
    const reconcileWithin = (root: Document | DocumentFragment | Element) => editorRootsWithin(root).forEach(controller.reconcile);

    document.addEventListener("click", (event) => {
        if (!(event.target instanceof Element)) return;
        const handled = controller.start(event.target)
            || controller.finish(event.target, document.activeElement instanceof Element ? document.activeElement : null);
        if (handled) event.preventDefault();
    });

    onAppPageReady((event) => reconcileWithin(detailRoot(event, "target")));
    document.addEventListener("htmx:afterSwap", (event) => reconcileWithin(detailRoot(event, "target")));
    document.addEventListener("htmx:beforeCleanupElement", (event) => {
        const cleanupRoot = detailTarget(event, "elt");
        if (cleanupRoot instanceof Element) controller.dispose(cleanupRoot);
    });
    if (document.readyState !== "loading") reconcileWithin(document);
}
