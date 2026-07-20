import {
    rosterShiftGroupHighlightMemberDomAttr,
    rosterShiftGroupHighlightSourceDomAttr,
    rosterStaffHighlightMemberDomAttr,
    rosterStaffHighlightOrderDomAttr,
    rosterStaffHighlightPinDomAttr,
    rosterStaffHighlightSourceDomAttr,
    surfaceDomAttr,
} from "../generated/contracts";
import { createLinkedHighlightController } from "../linked-highlight/runtime";
import { assertEqual, test } from "./harness";

class MiniClassList {
    private readonly values = new Set<string>();

    add(...classNames: string[]): void {
        classNames.forEach((className) => this.values.add(className));
    }

    remove(...classNames: string[]): void {
        classNames.forEach((className) => this.values.delete(className));
    }

    contains(className: string): boolean {
        return this.values.has(className);
    }
}

class MiniElement {
    readonly children: MiniElement[] = [];
    readonly classList = new MiniClassList();
    parent: MiniElement | null = null;
    clickCount = 0;
    private readonly attrs = new Map<string, string>();

    constructor(attrs: Record<string, string> = {}) {
        Object.entries(attrs).forEach(([name, value]) => this.attrs.set(name, value));
    }

    append(child: MiniElement): MiniElement {
        child.parent = this;
        this.children.push(child);
        return child;
    }

    removeChild(child: MiniElement): void {
        const childIndex = this.children.indexOf(child);
        if (childIndex < 0) return;
        this.children.splice(childIndex, 1);
        child.parent = null;
    }

    getAttribute(name: string): string | null {
        return this.attrs.get(name) ?? null;
    }

    setAttribute(name: string, value: string): void {
        this.attrs.set(name, value);
    }

    closest(selector: string): MiniElement | null {
        let current: MiniElement | null = this;
        while (current) {
            if (matchesAttributeSelector(current, selector)) return current;
            current = current.parent;
        }
        return null;
    }

    querySelectorAll(selector: string): MiniElement[] {
        const matches: MiniElement[] = [];
        const visit = (element: MiniElement) => {
            for (const child of element.children) {
                if (matchesAttributeSelector(child, selector)) matches.push(child);
                visit(child);
            }
        };
        visit(this);
        return matches;
    }

    click(): void {
        this.clickCount += 1;
    }
}

function matchesAttributeSelector(element: MiniElement, selector: string): boolean {
    if (selector.startsWith(".")) return element.classList.contains(selector.slice(1));
    const match = selector.match(/^\[([^\]]+)\]$/);
    return match ? element.getAttribute(match[1] ?? "") !== null : false;
}

function rosterMount(): MiniElement {
    return new MiniElement({ [surfaceDomAttr]: "roster" });
}

test("linked highlighting applies closed source/member/order effects inside one mount", () => {
    const controller = createLinkedHighlightController();
    const mount = rosterMount();
    const source = mount.append(new MiniElement({ [rosterStaffHighlightSourceDomAttr]: "opaque:staff-a" }));
    const pin = mount.append(new MiniElement({ [rosterStaffHighlightPinDomAttr]: "opaque:staff-a", "aria-pressed": "false" }));
    const first = mount.append(new MiniElement({
        [rosterStaffHighlightMemberDomAttr]: "opaque:staff-a",
        [rosterStaffHighlightOrderDomAttr]: "opaque:shift-a",
    }));
    const last = mount.append(new MiniElement({
        [rosterStaffHighlightMemberDomAttr]: "opaque:staff-a",
        [rosterStaffHighlightOrderDomAttr]: "opaque:shift-a",
    }));
    const unrelated = mount.append(new MiniElement({
        [rosterStaffHighlightMemberDomAttr]: "opaque:staff-b",
        [rosterStaffHighlightOrderDomAttr]: "opaque:shift-b",
    }));

    controller.pointerEntered(source as unknown as Element, null);

    assertEqual(source.classList.contains("is-linked-highlight-source"), true);
    assertEqual(first.classList.contains("is-linked-highlight-member"), true);
    assertEqual(last.classList.contains("is-linked-highlight-member"), true);
    assertEqual(first.classList.contains("is-linked-highlight-member-first"), true);
    assertEqual(last.classList.contains("is-linked-highlight-member-last"), true);
    assertEqual(unrelated.classList.contains("is-linked-highlight-member"), false);
    assertEqual(pin.getAttribute("aria-pressed"), "false");

    controller.pointerLeft(source as unknown as Element, null);
    assertEqual(source.classList.contains("is-linked-highlight-source"), false);
    assertEqual(first.classList.contains("is-linked-highlight-member"), false);

    assertEqual(controller.togglePin(pin as unknown as Element), true);
    assertEqual(pin.getAttribute("aria-pressed"), "true");
    assertEqual(first.classList.contains("is-linked-highlight-member"), true);

    controller.pointerEntered(unrelated as unknown as Element, null);
    assertEqual(first.classList.contains("is-linked-highlight-member"), true);
    assertEqual(unrelated.classList.contains("is-linked-highlight-member"), false);

    assertEqual(controller.togglePin(pin as unknown as Element), true);
    assertEqual(pin.getAttribute("aria-pressed"), "false");
    assertEqual(first.classList.contains("is-linked-highlight-member"), false);

    controller.togglePin(pin as unknown as Element);
    mount.removeChild(source);
    controller.reconcile(mount as unknown as Element);
    assertEqual(pin.getAttribute("aria-pressed"), "false");
    assertEqual(first.classList.contains("is-linked-highlight-member"), false);
});

test("linked highlighting preserves focus, keyboard activation, and duplicate-mount isolation", () => {
    const controller = createLinkedHighlightController();
    const firstMount = rosterMount();
    const secondMount = rosterMount();
    const firstSource = firstMount.append(new MiniElement({
        [rosterShiftGroupHighlightSourceDomAttr]: "opaque:shift",
        [rosterShiftGroupHighlightMemberDomAttr]: "opaque:shift",
    }));
    const firstPeer = firstMount.append(new MiniElement({ [rosterShiftGroupHighlightMemberDomAttr]: "opaque:shift" }));
    const duplicatePeer = secondMount.append(new MiniElement({ [rosterShiftGroupHighlightMemberDomAttr]: "opaque:shift" }));

    controller.focusEntered(firstSource as unknown as Element);
    assertEqual(firstSource.classList.contains("is-linked-highlight-member"), true);
    assertEqual(firstPeer.classList.contains("is-linked-highlight-member"), true);
    assertEqual(duplicatePeer.classList.contains("is-linked-highlight-member"), false);

    assertEqual(controller.activateKeyboard(firstSource as unknown as Element, "Enter"), true);
    assertEqual(firstSource.clickCount, 1);
    assertEqual(controller.activateKeyboard(firstSource as unknown as Element, "Escape"), false);

    controller.focusLeft(firstSource as unknown as Element, null);
    assertEqual(firstPeer.classList.contains("is-linked-highlight-member"), false);
});
