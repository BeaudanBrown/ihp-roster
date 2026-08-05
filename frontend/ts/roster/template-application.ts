import {
    InteractionDom,
    parseTemplateApplicationCardConfig,
    rosterTemplateApplicationFormDomAttr,
    rosterTemplateCancelDomAttr,
    rosterTemplateCardConfigDomAttr,
    rosterTemplateCardDomAttr,
    rosterTemplateDayTargetDomAttr,
    rosterTemplateTargetInputDomAttr,
    rosterTemplateWeekTargetDomAttr,
} from "../generated/contracts";
import { reduceTemplateApplicationSelection, type TemplateApplicationSelection } from "./template-application-selection";

const selectingClass = "is-template-day-targeting";
const selectedCardClass = "is-template-card-selected";
const cardSelector = `[${rosterTemplateCardDomAttr}]`;
const cardConfigSelector = `[${rosterTemplateCardConfigDomAttr}]`;
const dayTargetSelector = `[${rosterTemplateDayTargetDomAttr}]`;
const weekTargetSelector = `[${rosterTemplateWeekTargetDomAttr}]`;
const cancelSelector = `[${rosterTemplateCancelDomAttr}]`;
const formSelector = `[${rosterTemplateApplicationFormDomAttr}]`;
const targetInputSelector = `[${rosterTemplateTargetInputDomAttr}]`;
const rosterMountSelector = `[${InteractionDom.attributes.surface}]`;
interface MountSelectionSession {
    state: TemplateApplicationSelection;
    activeCard: Element | null;
}

const sessions = new WeakMap<Element, MountSelectionSession>();

export function enableRosterTemplateApplication(): () => void {
    if (typeof document === "undefined") return () => undefined;

    const click = (event: Event) => handleClick(event);
    const keydown = (event: KeyboardEvent) => handleKeydown(event);
    const cleanup = (event: Event) => {
        if (!(event.target instanceof Element)) return;
        if (event.target.matches(rosterMountSelector)) resetMount(event.target);
        event.target.querySelectorAll(rosterMountSelector).forEach(resetMount);
    };

    document.addEventListener("click", click, true);
    document.addEventListener("keydown", keydown);
    document.addEventListener("htmx:beforeCleanupElement", cleanup);

    return () => {
        document.removeEventListener("click", click, true);
        document.removeEventListener("keydown", keydown);
        document.removeEventListener("htmx:beforeCleanupElement", cleanup);
        document.querySelectorAll(rosterMountSelector).forEach(resetMount);
    };
}

function handleClick(event: Event): void {
    const target = event.target;
    if (!(target instanceof Element)) return;

    const mount = target.closest(rosterMountSelector);
    if (!mount) return;

    if (target.closest(cancelSelector)) {
        stopEvent(event);
        transition(mount, { kind: "cancel" });
        return;
    }

    if (target.closest(".roster-template-card-actions")) return;

    const card = target.closest(cardSelector);
    if (card && target.closest(".roster-template-card-apply")) {
        stopEvent(event);
        activateCard(mount, card);
        return;
    }

    const session = sessions.get(mount);
    if (session?.state.kind !== "selecting-day") return;

    const dayTarget = target.closest(dayTargetSelector);
    const targetKey = dayTarget ? dayTargetKey(dayTarget) : null;
    if (dayTarget && targetKey) {
        stopEvent(event);
        transition(mount, { kind: "activate-day", targetKey });
        return;
    }

    stopEvent(event);
    transition(mount, { kind: "invalid-area" });
}

function handleKeydown(event: KeyboardEvent): void {
    const target = event.target;
    if (!(target instanceof Element)) return;
    const mount = target.closest(rosterMountSelector);
    if (!mount || sessions.get(mount)?.state.kind !== "selecting-day") return;

    if (event.key === "Escape") {
        event.preventDefault();
        transition(mount, { kind: "escape" });
        return;
    }
    if (event.key !== "Enter" && event.key !== " " && event.key !== "Spacebar") return;

    const dayTarget = target.closest(dayTargetSelector);
    const targetKey = dayTarget ? dayTargetKey(dayTarget) : null;
    if (!targetKey) return;
    event.preventDefault();
    transition(mount, { kind: "activate-day", targetKey });
}

function activateCard(mount: Element, card: Element): void {
    const configOwner = card.matches(cardConfigSelector) ? card : card.querySelector(cardConfigSelector);
    if (!configOwner) return;

    let config: ReturnType<typeof parseTemplateApplicationCardConfig>;
    try {
        config = parseTemplateApplicationCardConfig(JSON.parse(configOwner.getAttribute(rosterTemplateCardConfigDomAttr) ?? ""));
    } catch {
        return;
    }

    const session = sessionFor(mount);
    session.activeCard = card;
    if (config.templateScale === "week") {
        const weekTargetKey = mount.querySelector(weekTargetSelector)?.getAttribute(InteractionDom.attributes.dropzoneKey);
        if (!weekTargetKey) return resetMount(mount);
        transition(mount, { kind: "activate-card", templateId: config.templateId, scale: "week", weekTargetKey });
        return;
    }
    if (config.templateScale !== "day") return resetMount(mount);
    transition(mount, { kind: "activate-card", templateId: config.templateId, scale: "day" });
}

function transition(mount: Element, event: Parameters<typeof reduceTemplateApplicationSelection>[1]): void {
    const session = sessionFor(mount);
    session.state = reduceTemplateApplicationSelection(session.state, event);

    if (session.state.kind === "commit") {
        const form = session.activeCard?.querySelector(formSelector);
        const targetInput = form?.querySelector(targetInputSelector);
        if (form instanceof HTMLFormElement && targetInput instanceof HTMLInputElement) {
            targetInput.value = session.state.targetKey;
            form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
        }
        resetMount(mount);
        return;
    }

    renderMount(mount, session);
}

function renderMount(mount: Element, session: MountSelectionSession): void {
    const selecting = session.state.kind === "selecting-day";
    mount.classList.toggle(selectingClass, selecting);
    session.activeCard?.classList.toggle(selectedCardClass, selecting);
    mount.querySelectorAll(cancelSelector).forEach((button) => {
        if (button instanceof HTMLElement) button.hidden = !selecting;
    });
    mount.querySelectorAll(dayTargetSelector).forEach((target) => {
        if (!(target instanceof HTMLElement)) return;
        target.hidden = !selecting;
        target.tabIndex = selecting ? 0 : -1;
    });

    if (!selecting) session.activeCard = null;
}

function resetMount(mount: Element): void {
    const session = sessions.get(mount);
    if (!session) return;
    session.state = { kind: "idle" };
    renderMount(mount, session);
    sessions.delete(mount);
}

function sessionFor(mount: Element): MountSelectionSession {
    const existing = sessions.get(mount);
    if (existing) return existing;
    const created: MountSelectionSession = { state: { kind: "idle" }, activeCard: null };
    sessions.set(mount, created);
    return created;
}

function dayTargetKey(target: Element): string | null {
    return target.closest(`[${InteractionDom.attributes.dropzoneKey}]`)?.getAttribute(InteractionDom.attributes.dropzoneKey) ?? null;
}

function stopEvent(event: Event): void {
    if (event.cancelable) event.preventDefault();
    event.stopImmediatePropagation();
}
