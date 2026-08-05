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
const rosterMountSelector = `[${InteractionDom.attributes.surface}="roster"]`;

let state: TemplateApplicationSelection = { kind: "idle" };
let activeMount: Element | null = null;
let activeCard: Element | null = null;

export function enableRosterTemplateApplication(): () => void {
    if (typeof document === "undefined") return () => undefined;

    const click = (event: Event) => handleClick(event);
    const keydown = (event: KeyboardEvent) => {
        if (state.kind !== "selecting-day") return;
        if (event.key === "Escape") {
            event.preventDefault();
            transition({ kind: "escape" });
            return;
        }
        if (event.key !== "Enter" && event.key !== " " && event.key !== "Spacebar") return;
        const target = event.target instanceof Element ? event.target.closest(dayTargetSelector) : null;
        const targetKey = target?.getAttribute(InteractionDom.attributes.dropzoneKey);
        if (!target || !targetKey || !activeMount?.contains(target)) return;
        event.preventDefault();
        transition({ kind: "activate-day", targetKey });
    };
    const cleanup = (event: Event) => {
        if (activeMount && event.target instanceof Node && (event.target === activeMount || event.target.contains(activeMount))) {
            resetPresentation();
        }
    };

    document.addEventListener("click", click, true);
    document.addEventListener("keydown", keydown);
    document.addEventListener("htmx:beforeCleanupElement", cleanup);

    return () => {
        document.removeEventListener("click", click, true);
        document.removeEventListener("keydown", keydown);
        document.removeEventListener("htmx:beforeCleanupElement", cleanup);
        resetPresentation();
    };
}

function handleClick(event: Event): void {
    const target = event.target;
    if (!(target instanceof Element)) return;

    if (target.closest(cancelSelector)) {
        event.preventDefault();
        event.stopImmediatePropagation();
        transition({ kind: "cancel" });
        return;
    }

    if (target.closest(".roster-template-card-actions")) return;

    const card = target.closest(cardSelector);
    if (card && target.closest(".roster-template-card-apply")) {
        event.preventDefault();
        event.stopImmediatePropagation();
        activateCard(card);
        return;
    }

    if (state.kind !== "selecting-day") return;

    const dayTarget = target.closest(dayTargetSelector);
    if (dayTarget && activeMount?.contains(dayTarget)) {
        const targetKey = dayTarget.getAttribute(InteractionDom.attributes.dropzoneKey);
        if (targetKey) {
            event.preventDefault();
            event.stopImmediatePropagation();
            transition({ kind: "activate-day", targetKey });
            return;
        }
    }

    if (activeMount?.contains(target)) {
        event.preventDefault();
        event.stopImmediatePropagation();
        transition({ kind: "invalid-area" });
    }
}

function activateCard(card: Element): void {
    const configOwner = card.matches(cardConfigSelector) ? card : card.querySelector(cardConfigSelector);
    if (!configOwner) return;

    let config: ReturnType<typeof parseTemplateApplicationCardConfig>;
    try {
        config = parseTemplateApplicationCardConfig(JSON.parse(configOwner.getAttribute(rosterTemplateCardConfigDomAttr) ?? ""));
    } catch {
        return;
    }

    const mount = card.closest(rosterMountSelector);
    if (!mount) return;

    activeMount = mount;
    activeCard = card;
    if (config.templateScale === "week") {
        const weekTarget = mount.querySelector(weekTargetSelector);
        const weekTargetKey = weekTarget?.getAttribute(InteractionDom.attributes.dropzoneKey);
        if (!weekTargetKey) return resetPresentation();
        transition({ kind: "activate-card", templateId: config.templateId, scale: "week", weekTargetKey });
        return;
    }
    if (config.templateScale !== "day") return resetPresentation();

    transition({ kind: "activate-card", templateId: config.templateId, scale: "day" });
}

function transition(event: Parameters<typeof reduceTemplateApplicationSelection>[1]): void {
    const next = reduceTemplateApplicationSelection(state, event);
    state = next;

    if (next.kind === "commit") {
        const card = activeCard;
        const form = card?.querySelector(formSelector);
        const targetInput = form?.querySelector(targetInputSelector);
        if (form instanceof HTMLFormElement && targetInput instanceof HTMLInputElement) {
            targetInput.value = next.targetKey;
            form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
        }
        resetPresentation();
        return;
    }

    renderPresentation();
}

function renderPresentation(): void {
    const selecting = state.kind === "selecting-day";
    activeMount?.classList.toggle(selectingClass, selecting);
    activeCard?.classList.toggle(selectedCardClass, selecting);
    activeMount?.querySelectorAll(cancelSelector).forEach((button) => {
        if (button instanceof HTMLElement) button.hidden = !selecting;
    });

    if (!selecting) {
        activeMount = null;
        activeCard = null;
    }
}

function resetPresentation(): void {
    state = { kind: "idle" };
    renderPresentation();
}
