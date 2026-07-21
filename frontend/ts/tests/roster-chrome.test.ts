import {
    rosterColumnEditDoneDomAttr,
    rosterColumnEditingDomAttr,
    rosterColumnEditingStates,
    rosterColumnEditorDomAttr,
    rosterColumnEditStartDomAttr,
    rosterFullscreenDomAttr,
    rosterFullscreenLabelDomAttr,
    rosterFullscreenRootDomAttr,
    rosterFullscreenStates,
    rosterFullscreenToggleDomAttr,
} from "../generated/contracts";
import {
    createRosterColumnEditController,
    type RosterColumnEditDiagnostic,
    type RosterColumnEditScheduler,
} from "../roster/column-edit";
import {
    createRosterFullscreenController,
    type RosterFullscreenDiagnostic,
} from "../roster/fullscreen-runtime";
import { assertDeepEqual, assertEqual, test } from "./harness";

class MiniClassList {
    private readonly values = new Set<string>();

    constructor(initial: string[] = []) {
        initial.forEach((value) => this.values.add(value));
    }

    toggle(value: string, force?: boolean): boolean {
        const enabled = force ?? !this.values.has(value);
        if (enabled) this.values.add(value);
        else this.values.delete(value);
        return enabled;
    }

    contains(value: string): boolean {
        return this.values.has(value);
    }
}

class MiniElement {
    readonly children: MiniElement[] = [];
    readonly classList: MiniClassList;
    parentElement: MiniElement | null = null;
    textContent: string | null = null;
    focusCount = 0;
    blurCount = 0;
    readonly id: string;
    private readonly attrs = new Map<string, string>();

    constructor(attrs: Record<string, string> = {}, id = "", classes: string[] = []) {
        this.id = id;
        this.classList = new MiniClassList(classes);
        Object.entries(attrs).forEach(([name, value]) => this.attrs.set(name, value));
    }

    append(child: MiniElement): MiniElement {
        child.parentElement = this;
        this.children.push(child);
        return child;
    }

    replaceChildren(...children: MiniElement[]): void {
        this.children.forEach((child) => { child.parentElement = null; });
        this.children.splice(0, this.children.length);
        children.forEach((child) => this.append(child));
    }

    getAttribute(name: string): string | null {
        return this.attrs.get(name) ?? null;
    }

    setAttribute(name: string, value: string): void {
        this.attrs.set(name, value);
    }

    matches(selector: string): boolean {
        const attribute = selector.match(/^\[([^\]=]+)(?:="([^"]*)")?\]$/);
        if (attribute) {
            const value = this.getAttribute(attribute[1] ?? "");
            return value !== null && (attribute[2] === undefined || value === attribute[2]);
        }
        const className = selector.match(/^\.([A-Za-z0-9_-]+)$/)?.[1];
        return className ? this.classList.contains(className) : false;
    }

    closest(selector: string): MiniElement | null {
        let current: MiniElement | null = this;
        while (current) {
            if (current.matches(selector)) return current;
            current = current.parentElement;
        }
        return null;
    }

    querySelectorAll(selector: string): MiniElement[] {
        const found: MiniElement[] = [];
        const visit = (owner: MiniElement) => {
            owner.children.forEach((child) => {
                if (child.matches(selector)) found.push(child);
                visit(child);
            });
        };
        visit(this);
        return found;
    }

    querySelector(selector: string): MiniElement | null {
        return this.querySelectorAll(selector)[0] ?? null;
    }

    contains(candidate: MiniElement): boolean {
        return candidate === this || this.children.some((child) => child.contains(candidate));
    }

    focus(): void {
        this.focusCount += 1;
    }

    blur(): void {
        this.blurCount += 1;
    }
}

function fullscreenFixture(id: string) {
    const root = new MiniElement({
        [rosterFullscreenRootDomAttr]: "true",
        [rosterFullscreenDomAttr]: rosterFullscreenStates.collapsed,
    }, `${id}-root`);
    const toggle = root.append(new MiniElement({ [rosterFullscreenToggleDomAttr]: "true" }, `${id}-toggle`));
    const icon = toggle.append(new MiniElement({}, `${id}-icon`, ["bi", "bi-fullscreen"]));
    const label = toggle.append(new MiniElement({ [rosterFullscreenLabelDomAttr]: "true" }, `${id}-label`));
    label.textContent = "Expand roster";
    return { root, toggle, icon, label };
}

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

test("roster fullscreen state and labels remain local to the generated root", () => {
    const first = fullscreenFixture("first");
    const second = fullscreenFixture("second");
    const controller = createRosterFullscreenController();

    assertEqual(controller.toggle(first.icon as unknown as Element), true);
    assertEqual(first.root.getAttribute(rosterFullscreenDomAttr), rosterFullscreenStates.expanded);
    assertEqual(second.root.getAttribute(rosterFullscreenDomAttr), rosterFullscreenStates.collapsed);
    assertEqual(first.toggle.getAttribute("aria-pressed"), "true");
    assertEqual(first.toggle.getAttribute("aria-label"), "Exit expanded roster");
    assertEqual(first.label.textContent, "Exit expanded roster");
    assertEqual(first.icon.classList.contains("bi-fullscreen-exit"), true);
    assertEqual(first.icon.classList.contains("bi-fullscreen"), false);
    assertEqual(first.toggle.focusCount, 1);
});

test("roster fullscreen reconciliation restores replacement controls and rejects malformed state", () => {
    const fixture = fullscreenFixture("replacement");
    const diagnostics: RosterFullscreenDiagnostic[] = [];
    const controller = createRosterFullscreenController((diagnostic) => diagnostics.push(diagnostic));
    fixture.root.setAttribute(rosterFullscreenDomAttr, rosterFullscreenStates.expanded);

    const replacementToggle = new MiniElement({ [rosterFullscreenToggleDomAttr]: "true" }, "replacement-toggle");
    const replacementIcon = replacementToggle.append(new MiniElement({}, "replacement-icon", ["bi", "bi-fullscreen"]));
    const replacementLabel = replacementToggle.append(new MiniElement({ [rosterFullscreenLabelDomAttr]: "true" }, "replacement-label"));
    fixture.root.replaceChildren(replacementToggle);

    assertEqual(controller.reconcile(fixture.root as unknown as Element), true);
    assertEqual(replacementToggle.getAttribute("aria-pressed"), "true");
    assertEqual(replacementLabel.textContent, "Exit expanded roster");
    assertEqual(replacementIcon.classList.contains("bi-fullscreen-exit"), true);

    fixture.root.setAttribute(rosterFullscreenDomAttr, "unknown");
    assertEqual(controller.reconcile(fixture.root as unknown as Element), false);
    assertEqual(diagnostics[0]?.code, "invalid-state");

    fixture.root.setAttribute(rosterFullscreenDomAttr, rosterFullscreenStates.collapsed);
    replacementToggle.setAttribute(rosterFullscreenToggleDomAttr, "invalid");
    assertEqual(controller.toggle(replacementIcon as unknown as Element), false);
    assertEqual(fixture.root.getAttribute(rosterFullscreenDomAttr), rosterFullscreenStates.collapsed);
    assertDeepEqual(diagnostics.map((diagnostic) => diagnostic.code), ["invalid-state", "invalid-toggle-role"]);
});

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
