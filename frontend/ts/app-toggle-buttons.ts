import {
    isTogglePresentationState,
    parseToggleConfig,
    toggleBreakRegionDomAttr,
    toggleConfigDomAttr,
    toggleInputDomAttr,
    toggleLabelStateDomAttr,
    toggleRootDomAttr,
    toggleTransportDomAttr,
    type ToggleConfig,
    type TogglePresentationState,
    type ToggleTarget,
} from "./generated/contracts";
import { rootFromTarget } from "./shared/dom";
import { assertNever } from "./shared/exhaustive";
import { detailTarget, onAppPageReady, onHtmxLoad } from "./shared/lifecycle";

export type ToggleDiagnosticCode =
    | "invalid-config"
    | "invalid-input-key"
    | "missing-root"
    | "invalid-root-key"
    | "missing-form"
    | "invalid-transport"
    | "invalid-presentation-state"
    | "invalid-label-state"
    | "invalid-break-region";

export type ToggleDiagnostic = {
    code: ToggleDiagnosticCode;
    inputId: string;
    message: string;
};

export type ToggleDiagnosticReporter = (diagnostic: ToggleDiagnostic) => void;

type ToggleControl = {
    input: HTMLInputElement;
    root: HTMLElement;
    form: HTMLFormElement;
    transport: HTMLInputElement;
    breakRegion: HTMLFieldSetElement | null;
    labels: ReadonlyArray<{ element: HTMLElement; state: TogglePresentationState }>;
    config: ToggleConfig;
};

const initializedControls = new WeakMap<HTMLInputElement, ToggleControl>();
const checkedClass = "is-toggle-checked";

function targetsEqual(left: ToggleTarget, right: ToggleTarget): boolean {
    if (left.tag !== right.tag) return false;
    if (left.tag === "omitted" || right.tag === "omitted") return true;
    return left.value === right.value;
}

export function parseToggleConfiguration(raw: string): ToggleConfig {
    const config = parseToggleConfig(JSON.parse(raw));
    if (config.transportKey.length === 0) {
        throw new Error("Toggle transportKey must not be empty");
    }
    if (config.breakRegionKey !== null && config.breakRegionKey.length === 0) {
        throw new Error("Toggle breakRegionKey must be null or non-empty");
    }
    if (targetsEqual(config.checkedTarget, config.uncheckedTarget)) {
        throw new Error("Toggle checkedTarget and uncheckedTarget must differ");
    }
    return config;
}

export function toggleTargetForChecked(config: ToggleConfig, checked: boolean): ToggleTarget {
    return checked ? config.checkedTarget : config.uncheckedTarget;
}

export function toggleTransportState(target: ToggleTarget): { value: string; disabled: boolean } {
    switch (target.tag) {
        case "value":
            return { value: target.value, disabled: false };
        case "omitted":
            return { value: "", disabled: true };
        default:
            return assertNever(target);
    }
}

function presentationStateForChecked(checked: boolean): TogglePresentationState {
    return checked ? "checked" : "unchecked";
}

function defaultDiagnosticReporter(diagnostic: ToggleDiagnostic): void {
    console.error?.("Invalid generated toggle configuration", diagnostic);
}

function diagnostic(input: HTMLInputElement, code: ToggleDiagnosticCode, message: string): ToggleDiagnostic {
    return { code, inputId: input.id, message };
}

function elementsWithRelationship(root: ParentNode, attribute: string, key: string): Element[] {
    return Array.from(root.querySelectorAll(`[${attribute}]`)).filter((element) => element.getAttribute(attribute) === key);
}

function readToggleControl(input: HTMLInputElement, report: ToggleDiagnosticReporter): ToggleControl | null {
    const rawConfig = input.getAttribute(toggleConfigDomAttr);
    let config: ToggleConfig;
    try {
        if (rawConfig === null) throw new Error(`Missing ${toggleConfigDomAttr}`);
        config = parseToggleConfiguration(rawConfig);
    } catch (error) {
        report(diagnostic(input, "invalid-config", error instanceof Error ? error.message : String(error)));
        return null;
    }

    if (input.getAttribute(toggleInputDomAttr) !== config.transportKey) {
        report(diagnostic(input, "invalid-input-key", "Toggle input relationship does not match transportKey"));
        return null;
    }

    const root = input.closest(`[${toggleRootDomAttr}]`);
    if (!(root instanceof HTMLElement)) {
        report(diagnostic(input, "missing-root", "Toggle input has no generated root"));
        return null;
    }
    if (root.getAttribute(toggleRootDomAttr) !== config.transportKey) {
        report(diagnostic(input, "invalid-root-key", "Toggle root relationship does not match transportKey"));
        return null;
    }

    const form = input.form;
    if (!(form instanceof HTMLFormElement)) {
        report(diagnostic(input, "missing-form", "Toggle input must belong to a form"));
        return null;
    }

    const transports = elementsWithRelationship(form, toggleTransportDomAttr, config.transportKey);
    if (transports.length !== 1 || !(transports[0] instanceof HTMLInputElement) || transports[0].type !== "hidden" || transports[0].name.length === 0) {
        report(diagnostic(input, "invalid-transport", "Toggle must resolve exactly one named hidden transport within input.form"));
        return null;
    }
    const transport = transports[0];

    const expectedPresentation = presentationStateForChecked(input.checked);
    if (config.presentationState !== expectedPresentation) {
        report(diagnostic(input, "invalid-presentation-state", "Rendered checkbox state disagrees with ToggleConfig presentationState"));
        return null;
    }
    const expectedTransport = toggleTransportState(toggleTargetForChecked(config, input.checked));
    if (transport.value !== expectedTransport.value || transport.disabled !== expectedTransport.disabled) {
        report(diagnostic(input, "invalid-transport", "Rendered transport state disagrees with ToggleConfig"));
        return null;
    }

    const labels: Array<{ element: HTMLElement; state: TogglePresentationState }> = [];
    const seenStates = new Set<TogglePresentationState>();
    for (const label of root.querySelectorAll(`[${toggleLabelStateDomAttr}]`)) {
        const state = label.getAttribute(toggleLabelStateDomAttr);
        if (!(label instanceof HTMLElement) || !isTogglePresentationState(state) || seenStates.has(state)) {
            report(diagnostic(input, "invalid-label-state", "Toggle labels must use unique generated presentation states"));
            return null;
        }
        seenStates.add(state);
        labels.push({ element: label, state });
    }
    if (labels.length !== 0 && labels.length !== 2) {
        report(diagnostic(input, "invalid-label-state", "State-labelled toggles must render checked and unchecked labels"));
        return null;
    }

    let breakRegion: HTMLFieldSetElement | null = null;
    if (config.breakRegionKey !== null) {
        const regions = elementsWithRelationship(form, toggleBreakRegionDomAttr, config.breakRegionKey);
        if (regions.length !== 1 || !(regions[0] instanceof HTMLFieldSetElement) || regions[0].id.length === 0 || input.getAttribute("aria-controls") !== regions[0].id) {
            report(diagnostic(input, "invalid-break-region", "Toggle must resolve one aria-related break fieldset within input.form"));
            return null;
        }
        breakRegion = regions[0];
    }

    return { input, root, form, transport, breakRegion, labels, config };
}

function synchronizeToggle(control: ToggleControl): void {
    const { input, root, transport, breakRegion, labels, config } = control;
    const checked = input.checked;
    const transportState = toggleTransportState(toggleTargetForChecked(config, checked));

    // This must happen before requestSubmit so HTMX and native serialization see
    // the target represented by the user's new checkbox state.
    transport.value = transportState.value;
    transport.disabled = transportState.disabled;

    root.classList.toggle(checkedClass, checked);
    root.setAttribute("aria-pressed", String(checked));
    if (input.getAttribute("role") === "switch") {
        input.setAttribute("aria-checked", String(checked));
    }
    for (const label of labels) {
        label.element.hidden = label.state !== presentationStateForChecked(checked);
    }
    if (breakRegion !== null) {
        breakRegion.disabled = !checked;
        breakRegion.setAttribute("aria-disabled", String(!checked));
    }
}

function initializeToggle(input: HTMLInputElement, report: ToggleDiagnosticReporter): ToggleControl | null {
    const existing = initializedControls.get(input);
    if (existing !== undefined) return existing;

    const control = readToggleControl(input, report);
    if (control === null) return null;
    initializedControls.set(input, control);
    synchronizeToggle(control);
    return control;
}

function toggleInputsWithin(target: unknown): HTMLInputElement[] {
    const root = rootFromTarget(target);
    const inputs = Array.from(root.querySelectorAll(`[${toggleInputDomAttr}]`)).filter((element): element is HTMLInputElement => element instanceof HTMLInputElement);
    if (root instanceof HTMLInputElement && root.hasAttribute(toggleInputDomAttr)) {
        inputs.unshift(root);
    }
    return inputs;
}

export function initializeToggleButtons(target: unknown, report: ToggleDiagnosticReporter = defaultDiagnosticReporter): void {
    for (const input of toggleInputsWithin(target)) {
        initializeToggle(input, report);
    }
}

function handleToggleChange(event: Event): void {
    if (!(event.target instanceof HTMLInputElement) || !event.target.hasAttribute(toggleInputDomAttr)) return;
    const control = initializeToggle(event.target, defaultDiagnosticReporter);
    if (control === null) return;

    synchronizeToggle(control);
    if (control.config.submissionPolicy === "immediate") {
        control.form.requestSubmit();
    }
}

function enableAppToggleButtons(): void {
    if (typeof window === "undefined") return;

    // Capture guarantees transport synchronization precedes any target/bubble
    // listener that might serialize the containing form.
    document.addEventListener("change", handleToggleChange, true);
    onAppPageReady((event) => {
        initializeToggleButtons(detailTarget(event, "target"));
    });
    onHtmxLoad((event) => {
        initializeToggleButtons(detailTarget(event, "elt"));
    });

    if (document.readyState !== "loading") {
        initializeToggleButtons(document.body);
    }
}

enableAppToggleButtons();
