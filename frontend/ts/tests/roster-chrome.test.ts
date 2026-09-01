import {
    rosterColumnEditDoneDomAttr,
    rosterColumnEditingDomAttr,
    rosterColumnEditingStates,
    rosterColumnEditorDomAttr,
    rosterColumnEditStartDomAttr,
} from "../generated/contracts";
import {
    createRosterColumnEditController,
    type RosterColumnEditDiagnostic,
    type RosterColumnEditScheduler,
} from "../roster/column-edit";
import { assertDeepEqual, assertEqual, test } from "./harness";
import { MiniElement } from "./mini-dom";

function columnEditorFixture(id: string) {
    const editor = new MiniElement({
        [rosterColumnEditorDomAttr]: "true",
        [rosterColumnEditingDomAttr]: rosterColumnEditingStates.inactive,
    }, `${id}-editor`);
    const start = editor.append(new MiniElement({ [rosterColumnEditStartDomAttr]: "true" }, `${id}-start`));
    const done = editor.append(new MiniElement({ [rosterColumnEditDoneDomAttr]: "true" }, `${id}-done`));
    const input = editor.append(new MiniElement({}, `${id}-input`));
    return { editor, start, done, input };
}

class FakeScheduler implements RosterColumnEditScheduler {
    private nextId = 1;
    private readonly handlers = new Map<number, () => void>();

    setTimeout(handler: () => void): number {
        const id = this.nextId++;
        this.handlers.set(id, handler);
        return id;
    }

    clearTimeout(timerId: number): void {
        this.handlers.delete(timerId);
    }

    runAll(): void {
        const handlers = Array.from(this.handlers.values());
        this.handlers.clear();
        handlers.forEach((handler) => handler());
    }

    pendingCount(): number {
        return this.handlers.size;
    }
}

test("roster column editing is mount-local and waits for focused autosave blur", () => {
    const first = columnEditorFixture("first");
    const second = columnEditorFixture("second");
    const scheduler = new FakeScheduler();
    const controller = createRosterColumnEditController(undefined, scheduler);

    assertEqual(controller.start(first.start as unknown as Element), true);
    assertEqual(first.editor.getAttribute(rosterColumnEditingDomAttr), rosterColumnEditingStates.active);
    assertEqual(first.start.getAttribute("aria-pressed"), "true");
    assertEqual(second.editor.getAttribute(rosterColumnEditingDomAttr), rosterColumnEditingStates.inactive);

    assertEqual(controller.finish(first.done as unknown as Element, first.input as unknown as Element), true);
    assertEqual(first.input.blurCount, 1);
    assertEqual(first.editor.getAttribute(rosterColumnEditingDomAttr), rosterColumnEditingStates.active);
    assertEqual(scheduler.pendingCount(), 1);
    scheduler.runAll();
    assertEqual(first.editor.getAttribute(rosterColumnEditingDomAttr), rosterColumnEditingStates.inactive);
    assertEqual(first.start.getAttribute("aria-pressed"), "false");
});

test("roster column-edit cleanup cancels detached timers and replacement roots keep server state", () => {
    const fixture = columnEditorFixture("cleanup");
    const replacement = columnEditorFixture("replacement");
    const scheduler = new FakeScheduler();
    const diagnostics: RosterColumnEditDiagnostic[] = [];
    const controller = createRosterColumnEditController((diagnostic) => diagnostics.push(diagnostic), scheduler);

    controller.start(fixture.start as unknown as Element);
    controller.finish(fixture.done as unknown as Element, fixture.input as unknown as Element);
    controller.dispose(fixture.editor as unknown as Element);
    assertEqual(scheduler.pendingCount(), 0);
    scheduler.runAll();
    assertEqual(fixture.editor.getAttribute(rosterColumnEditingDomAttr), rosterColumnEditingStates.active);

    assertEqual(controller.reconcile(replacement.editor as unknown as Element), true);
    assertEqual(replacement.editor.getAttribute(rosterColumnEditingDomAttr), rosterColumnEditingStates.inactive);
    replacement.editor.setAttribute(rosterColumnEditingDomAttr, "unknown");
    assertEqual(controller.reconcile(replacement.editor as unknown as Element), false);
    assertDeepEqual(diagnostics.map((diagnostic) => diagnostic.code), ["invalid-state"]);
});
