import {
    FrontendSurfaceLinkedHighlightRegistry,
    isFrontendSurfaceName,
    surfaceDomAttr,
    type FrontendSurfaceLinkedHighlightDefinition,
    type FrontendSurfaceLinkedHighlightEffect,
} from "../generated/contracts";
import { assertNever } from "../shared/exhaustive";
import { onAppPageReady } from "../shared/lifecycle";

const sourceHighlightClass = "is-linked-highlight-source";
const memberHighlightClass = "is-linked-highlight-member";
const firstMemberHighlightClass = "is-linked-highlight-member-first";
const lastMemberHighlightClass = "is-linked-highlight-member-last";
const effectClasses = [
    sourceHighlightClass,
    memberHighlightClass,
    firstMemberHighlightClass,
    lastMemberHighlightClass,
] as const;

type ElementLike = {
    classList: {
        add: (...classNames: string[]) => void;
        remove: (...classNames: string[]) => void;
    };
    getAttribute: (name: string) => string | null;
    setAttribute: (name: string, value: string) => void;
    closest: (selector: string) => Element | null;
    querySelectorAll: (selector: string) => Iterable<Element>;
    click?: () => void;
};

type QueryRootLike = {
    querySelectorAll: (selector: string) => Iterable<Element>;
};

type HighlightState = {
    hoverKey: string | null;
    focusKey: string | null;
    pinnedKey: string | null;
};

type SourceContext = {
    mount: ElementLike;
    definition: FrontendSurfaceLinkedHighlightDefinition;
    source: ElementLike;
    membershipKey: string;
};

type PinContext = {
    mount: ElementLike;
    definition: FrontendSurfaceLinkedHighlightDefinition;
    pin: ElementLike;
    membershipKey: string;
};

export type LinkedHighlightPinChange = {
    mount: Element;
    pinRoleAttribute: string;
    pinnedKey: string | null;
};

export type LinkedHighlightControllerOptions = {
    onPinChange?: (change: LinkedHighlightPinChange) => void;
};

export type LinkedHighlightController = {
    pointerEntered: (target: Element, relatedTarget: Element | null) => void;
    pointerLeft: (target: Element, relatedTarget: Element | null) => void;
    focusEntered: (target: Element) => void;
    focusLeft: (target: Element, relatedTarget: Element | null) => void;
    togglePin: (target: Element) => boolean;
    activateKeyboard: (target: Element, key: string) => boolean;
    reconcile: (root: Document | Element) => void;
};

export function createLinkedHighlightController(options: LinkedHighlightControllerOptions = {}): LinkedHighlightController {
    const statesByMount = new WeakMap<object, Map<string, HighlightState>>();

    function stateFor(mount: ElementLike, definition: FrontendSurfaceLinkedHighlightDefinition): HighlightState {
        let mountStates = statesByMount.get(mount as object);
        if (!mountStates) {
            mountStates = new Map();
            statesByMount.set(mount as object, mountStates);
        }

        let state = mountStates.get(definition.name);
        if (!state) {
            state = { hoverKey: null, focusKey: null, pinnedKey: null };
            mountStates.set(definition.name, state);
        }
        return state;
    }

    function pointerEntered(target: Element, relatedTarget: Element | null): void {
        const context = sourceContext(target);
        if (!context || !context.definition.activations.includes("hover")) return;
        if (relatedSourceMatches(context, relatedTarget)) return;

        stateFor(context.mount, context.definition).hoverKey = context.membershipKey;
        refreshMount(context.mount);
    }

    function pointerLeft(target: Element, relatedTarget: Element | null): void {
        const context = sourceContext(target);
        if (!context || !context.definition.activations.includes("hover")) return;
        if (relatedSourceMatches(context, relatedTarget)) return;

        const state = stateFor(context.mount, context.definition);
        if (state.hoverKey === context.membershipKey) state.hoverKey = null;
        refreshMount(context.mount);
    }

    function focusEntered(target: Element): void {
        const context = sourceContext(target);
        if (!context || !context.definition.activations.includes("focus")) return;

        stateFor(context.mount, context.definition).focusKey = context.membershipKey;
        refreshMount(context.mount);
    }

    function focusLeft(target: Element, relatedTarget: Element | null): void {
        const context = sourceContext(target);
        if (!context || !context.definition.activations.includes("focus")) return;
        if (relatedSourceMatches(context, relatedTarget)) return;

        const state = stateFor(context.mount, context.definition);
        if (state.focusKey === context.membershipKey) state.focusKey = null;
        refreshMount(context.mount);
    }

    function togglePin(target: Element): boolean {
        const context = pinContext(target);
        if (!context || !context.definition.activations.includes("pin")) return false;

        const state = stateFor(context.mount, context.definition);
        if (state.pinnedKey === context.membershipKey) {
            state.pinnedKey = null;
            state.hoverKey = null;
            state.focusKey = null;
        } else {
            state.pinnedKey = context.membershipKey;
        }
        refreshMount(context.mount);
        options.onPinChange?.({
            mount: context.mount as unknown as Element,
            pinRoleAttribute: context.definition.pinRoleAttribute ?? "",
            pinnedKey: state.pinnedKey,
        });
        return true;
    }

    function activateKeyboard(target: Element, key: string): boolean {
        const context = sourceContext(target);
        if (!context || context.source !== (target as unknown as ElementLike)) return false;
        if (!context.definition.activations.includes("keyboard")) return false;
        if (key !== "Enter" && key !== " ") return false;

        context.source.click?.();
        return true;
    }

    function reconcile(root: Document | Element): void {
        const queryRoot = root as unknown as QueryRootLike;
        const mounts = Array.from(queryRoot.querySelectorAll(`[${surfaceDomAttr}]`)).filter(isElementLike) as unknown as ElementLike[];
        if (isElementLike(root) && root.getAttribute(surfaceDomAttr) !== null) mounts.unshift(root as unknown as ElementLike);

        for (const mount of mounts) {
            for (const definition of definitionsForMount(mount)) {
                const state = stateFor(mount, definition);
                if (state.pinnedKey && !sourceExists(mount, definition, state.pinnedKey)) {
                    state.pinnedKey = null;
                    if (definition.pinRoleAttribute) {
                        options.onPinChange?.({
                            mount: mount as unknown as Element,
                            pinRoleAttribute: definition.pinRoleAttribute,
                            pinnedKey: null,
                        });
                    }
                }
                if (state.hoverKey && !sourceExists(mount, definition, state.hoverKey)) state.hoverKey = null;
                if (state.focusKey && !sourceExists(mount, definition, state.focusKey)) state.focusKey = null;
            }
            refreshMount(mount);
        }
    }

    function refreshMount(mount: ElementLike): void {
        const definitions = definitionsForMount(mount);
        clearEffectClasses(mount);

        for (const definition of definitions) {
            const state = stateFor(mount, definition);
            const activeKey = state.pinnedKey ?? state.focusKey ?? state.hoverKey ?? defaultKeyFor(mount, definition);
            if (activeKey) applyEffects(mount, definition, activeKey);
            syncPinControls(mount, definition, state.pinnedKey);
        }
    }

    return {
        pointerEntered,
        pointerLeft,
        focusEntered,
        focusLeft,
        togglePin,
        activateKeyboard,
        reconcile,
    };
}

function sourceContext(target: unknown): SourceContext | null {
    if (!isElementLike(target)) return null;
    const mount = closestSurfaceMount(target);
    if (!mount) return null;

    for (const definition of definitionsForMount(mount)) {
        const source = closestOwnedRole(target, mount, definition.sourceRoleAttribute);
        const membershipKey = source?.getAttribute(definition.sourceRoleAttribute) ?? "";
        if (source && membershipKey !== "") return { mount, definition, source, membershipKey };
    }
    return null;
}

function pinContext(target: unknown): PinContext | null {
    if (!isElementLike(target)) return null;
    const mount = closestSurfaceMount(target);
    if (!mount) return null;

    for (const definition of definitionsForMount(mount)) {
        if (!definition.pinRoleAttribute) continue;
        const pin = closestOwnedRole(target, mount, definition.pinRoleAttribute);
        const membershipKey = pin?.getAttribute(definition.pinRoleAttribute) ?? "";
        if (pin && membershipKey !== "") return { mount, definition, pin, membershipKey };
    }
    return null;
}

function relatedSourceMatches(context: SourceContext, relatedTarget: Element | null): boolean {
    if (!relatedTarget || !isElementLike(relatedTarget)) return false;
    const relatedSource = closestOwnedRole(relatedTarget, context.mount, context.definition.sourceRoleAttribute);
    return relatedSource?.getAttribute(context.definition.sourceRoleAttribute) === context.membershipKey;
}

function closestOwnedRole(target: ElementLike, mount: ElementLike, attribute: string): ElementLike | null {
    const candidate = target.closest(`[${attribute}]`);
    if (!isElementLike(candidate)) return null;
    return closestSurfaceMount(candidate) === mount ? candidate : null;
}

function closestSurfaceMount(target: ElementLike): ElementLike | null {
    const mount = target.closest(`[${surfaceDomAttr}]`);
    return isElementLike(mount) ? mount : null;
}

function definitionsForMount(mount: ElementLike): ReadonlyArray<FrontendSurfaceLinkedHighlightDefinition> {
    const surface = mount.getAttribute(surfaceDomAttr);
    return isFrontendSurfaceName(surface) ? FrontendSurfaceLinkedHighlightRegistry[surface] : [];
}

function defaultKeyFor(mount: ElementLike, definition: FrontendSurfaceLinkedHighlightDefinition): string | null {
    if (!definition.defaultRoleAttribute || !definition.activations.includes("default")) return null;
    const defaultOwner = Array.from(mount.querySelectorAll(`[${definition.defaultRoleAttribute}]`))
        .filter(isElementLike)
        .find((element) => closestSurfaceMount(element) === mount);
    const defaultKey = defaultOwner?.getAttribute(definition.defaultRoleAttribute) ?? "";
    return defaultKey === "" ? null : defaultKey;
}

function sourceExists(mount: ElementLike, definition: FrontendSurfaceLinkedHighlightDefinition, membershipKey: string): boolean {
    return elementsForKey(mount, definition.sourceRoleAttribute, membershipKey).length > 0;
}

function clearEffectClasses(mount: ElementLike): void {
    const highlightedElements = new Set<ElementLike>();
    for (const className of effectClasses) {
        Array.from(mount.querySelectorAll(`.${className}`))
            .filter(isElementLike)
            .filter((element) => closestSurfaceMount(element) === mount)
            .forEach((element) => highlightedElements.add(element));
    }
    highlightedElements.forEach((element) => element.classList.remove(...effectClasses));
}

function applyEffects(mount: ElementLike, definition: FrontendSurfaceLinkedHighlightDefinition, membershipKey: string): void {
    const sources = elementsForKey(mount, definition.sourceRoleAttribute, membershipKey);
    const members = elementsForKey(mount, definition.memberRoleAttribute, membershipKey);

    for (const effect of definition.effects) {
        applyEffect(effect, definition, sources, members);
    }
}

function applyEffect(
    effect: FrontendSurfaceLinkedHighlightEffect,
    definition: FrontendSurfaceLinkedHighlightDefinition,
    sources: ElementLike[],
    members: ElementLike[],
): void {
    switch (effect) {
        case "matching-source":
            sources.forEach((source) => source.classList.add(sourceHighlightClass));
            return;
        case "matching-member":
            members.forEach((member) => member.classList.add(memberHighlightClass));
            return;
        case "ordered-member-bounds":
            markOrderedMemberBounds(definition, members);
            return;
        default:
            assertNever(effect);
    }
}

function markOrderedMemberBounds(definition: FrontendSurfaceLinkedHighlightDefinition, members: ElementLike[]): void {
    if (!definition.orderStateAttribute) return;
    const membersByOrderKey = new Map<string, ElementLike[]>();

    for (const member of members) {
        const orderKey = member.getAttribute(definition.orderStateAttribute);
        if (!orderKey) continue;
        const orderedMembers = membersByOrderKey.get(orderKey) ?? [];
        orderedMembers.push(member);
        membersByOrderKey.set(orderKey, orderedMembers);
    }

    for (const orderedMembers of membersByOrderKey.values()) {
        orderedMembers[0]?.classList.add(firstMemberHighlightClass);
        orderedMembers[orderedMembers.length - 1]?.classList.add(lastMemberHighlightClass);
    }
}

function syncPinControls(mount: ElementLike, definition: FrontendSurfaceLinkedHighlightDefinition, pinnedKey: string | null): void {
    if (!definition.pinRoleAttribute) return;
    for (const pin of ownedRoleElements(mount, definition.pinRoleAttribute)) {
        pin.setAttribute("aria-pressed", pin.getAttribute(definition.pinRoleAttribute) === pinnedKey ? "true" : "false");
    }
}

function elementsForKey(mount: ElementLike, attribute: string, membershipKey: string): ElementLike[] {
    return ownedRoleElements(mount, attribute)
        .filter((element) => element.getAttribute(attribute) === membershipKey);
}

function ownedRoleElements(mount: ElementLike, attribute: string): ElementLike[] {
    return Array.from(mount.querySelectorAll(`[${attribute}]`))
        .filter(isElementLike)
        .filter((element) => closestSurfaceMount(element) === mount);
}

function isElementLike(value: unknown): value is ElementLike {
    if (value === null || typeof value !== "object") return false;
    const candidate = value as Partial<ElementLike>;
    return Boolean(candidate.classList)
        && typeof candidate.getAttribute === "function"
        && typeof candidate.setAttribute === "function"
        && typeof candidate.closest === "function"
        && typeof candidate.querySelectorAll === "function";
}

let browserRuntimeEnabled = false;

export function enableFrontendSurfaceLinkedHighlight(options: LinkedHighlightControllerOptions = {}): void {
    if (browserRuntimeEnabled || typeof document === "undefined") return;
    browserRuntimeEnabled = true;

    const controller = createLinkedHighlightController(options);

    document.addEventListener("mouseover", (event) => {
        controller.pointerEntered(event.target as Element, relatedElement(event));
    });
    document.addEventListener("mouseout", (event) => {
        controller.pointerLeft(event.target as Element, relatedElement(event));
    });
    document.addEventListener("focusin", (event) => {
        controller.focusEntered(event.target as Element);
    });
    document.addEventListener("focusout", (event) => {
        controller.focusLeft(event.target as Element, relatedElement(event));
    });
    document.addEventListener("click", (event) => {
        if (!controller.togglePin(event.target as Element)) return;
        event.preventDefault();
        event.stopPropagation();
    }, true);
    document.addEventListener("keydown", (event) => {
        if (!controller.activateKeyboard(event.target as Element, event.key)) return;
        event.preventDefault();
    });

    onAppPageReady(() => controller.reconcile(document));
    controller.reconcile(document);
}

function relatedElement(event: MouseEvent | FocusEvent): Element | null {
    return isElementLike(event.relatedTarget) ? event.relatedTarget as unknown as Element : null;
}
