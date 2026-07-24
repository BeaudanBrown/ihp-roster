import {
    orderedRangeAvailabilityDomAttr,
    orderedRangeConfigDomAttr,
    orderedRangeEndDomAttr,
    orderedRangeEndPositionProperty,
    orderedRangeRootDomAttr,
    orderedRangeStartDomAttr,
    orderedRangeStartPositionProperty,
    orderedRangeStateDomAttr,
    type OrderedRangeConfig,
    type OrderedRangeState,
} from "./generated/contracts";
import {
    orderedRangeLabelForValue,
    orderedRangePositionPercent,
    orderedRangeStateForInput,
    parseOrderedRangeConfiguration,
    parseOrderedRangeStateConfiguration,
    type OrderedRangeEndpoint,
} from "./ordered-range/configuration";
import { rootFromTarget } from "./shared/dom";
import { detailTarget, onAppPageReady, onHtmxLoad } from "./shared/lifecycle";

export type OrderedRangeDiagnosticCode =
    | "invalid-config"
    | "invalid-state"
    | "invalid-start"
    | "invalid-end"
    | "invalid-availability"
    | "invalid-output"
    | "rendered-state-mismatch"
    | "invalid-input-value";

export type OrderedRangeDiagnostic = {
    code: OrderedRangeDiagnosticCode;
    rootId: string;
    message: string;
};

export type OrderedRangeDiagnosticReporter = (diagnostic: OrderedRangeDiagnostic) => void;

type OrderedRangeControl = {
    root: HTMLElement;
    startInput: HTMLInputElement;
    endInput: HTMLInputElement;
    availabilityInput: HTMLInputElement;
    startOutput: HTMLOutputElement;
    endOutput: HTMLOutputElement;
    config: OrderedRangeConfig;
    state: OrderedRangeState;
    report: OrderedRangeDiagnosticReporter;
};

const initializedControls = new WeakMap<HTMLElement, OrderedRangeControl>();

function defaultDiagnosticReporter(diagnostic: OrderedRangeDiagnostic): void {
    console.error?.("Invalid generated ordered-range configuration", diagnostic);
}

function diagnostic(
    root: HTMLElement,
    code: OrderedRangeDiagnosticCode,
    message: string,
): OrderedRangeDiagnostic {
    return { code, rootId: root.id, message };
}

function exactlyOneWithin<T extends Element>(
    root: ParentNode,
    selector: string,
    isExpected: (element: Element) => element is T,
): T | null {
    const matches = Array.from(root.querySelectorAll(selector));
    return matches.length === 1 && isExpected(matches[0]) ? matches[0] : null;
}

function outputForInput(root: HTMLElement, input: HTMLInputElement): HTMLOutputElement | null {
    if (input.id.length === 0) return null;
    const outputs = Array.from(root.querySelectorAll("output[for]"))
        .filter((output): output is HTMLOutputElement => (
            output instanceof HTMLOutputElement
            && output.getAttribute("for") === input.id
        ));
    return outputs.length === 1 ? outputs[0] : null;
}

function readOrderedRangeControl(
    root: HTMLElement,
    report: OrderedRangeDiagnosticReporter,
): OrderedRangeControl | null {
    let config: OrderedRangeConfig;
    const rawConfig = root.getAttribute(orderedRangeConfigDomAttr);
    try {
        if (rawConfig === null) throw new Error(`Missing ${orderedRangeConfigDomAttr}`);
        config = parseOrderedRangeConfiguration(rawConfig);
    } catch (error) {
        report(diagnostic(root, "invalid-config", error instanceof Error ? error.message : String(error)));
        return null;
    }

    let state: OrderedRangeState;
    const rawState = root.getAttribute(orderedRangeStateDomAttr);
    try {
        if (rawState === null) throw new Error(`Missing ${orderedRangeStateDomAttr}`);
        state = parseOrderedRangeStateConfiguration(config, rawState);
    } catch (error) {
        report(diagnostic(root, "invalid-state", error instanceof Error ? error.message : String(error)));
        return null;
    }

    const isRangeInput = (element: Element): element is HTMLInputElement => (
        element instanceof HTMLInputElement
        && element.type === "range"
        && element.name.length > 0
        && element.id.length > 0
    );
    const startInput = exactlyOneWithin(root, `[${orderedRangeStartDomAttr}]`, isRangeInput);
    if (startInput === null) {
        report(diagnostic(root, "invalid-start", "Ordered range must contain exactly one named start range input"));
        return null;
    }
    const endInput = exactlyOneWithin(root, `[${orderedRangeEndDomAttr}]`, isRangeInput);
    if (endInput === null || endInput === startInput) {
        report(diagnostic(root, "invalid-end", "Ordered range must contain exactly one distinct named end range input"));
        return null;
    }

    const availabilityRole = exactlyOneWithin(
        root,
        `[${orderedRangeAvailabilityDomAttr}]`,
        (element): element is HTMLElement => element instanceof HTMLElement,
    );
    const availabilityInput = availabilityRole === null
        ? null
        : exactlyOneWithin(
            availabilityRole,
            'input[type="checkbox"]',
            (element): element is HTMLInputElement => element instanceof HTMLInputElement,
        );
    if (availabilityInput === null) {
        report(diagnostic(root, "invalid-availability", "Ordered range availability role must contain exactly one native checkbox"));
        return null;
    }

    const startOutput = outputForInput(root, startInput);
    const endOutput = outputForInput(root, endInput);
    if (startOutput === null || endOutput === null || startOutput === endOutput) {
        report(diagnostic(root, "invalid-output", "Ordered range endpoints must each have one native output relationship"));
        return null;
    }

    const expectedMinimum = String(config.minimumValue);
    const expectedMaximum = String(config.maximumValue);
    const expectedStep = String(config.stepValue);
    const renderedStateMatches = (
        startInput.min === expectedMinimum
        && startInput.max === expectedMaximum
        && startInput.step === expectedStep
        && endInput.min === expectedMinimum
        && endInput.max === expectedMaximum
        && endInput.step === expectedStep
        && startInput.value === String(state.startValue)
        && endInput.value === String(state.endValue)
        && availabilityInput.checked === state.available
        && startInput.disabled === !state.available
        && endInput.disabled === !state.available
        && startOutput.textContent?.trim() === orderedRangeLabelForValue(config, state.startValue)
        && endOutput.textContent?.trim() === orderedRangeLabelForValue(config, state.endValue)
    );
    if (!renderedStateMatches) {
        report(diagnostic(root, "rendered-state-mismatch", "Rendered ordered range disagrees with its exact configuration or state"));
        return null;
    }

    return {
        root,
        startInput,
        endInput,
        availabilityInput,
        startOutput,
        endOutput,
        config,
        state,
        report,
    };
}

function synchronizeOrderedRange(control: OrderedRangeControl): void {
    const {
        root,
        startInput,
        endInput,
        availabilityInput,
        startOutput,
        endOutput,
        config,
        state,
    } = control;

    startInput.value = String(state.startValue);
    endInput.value = String(state.endValue);
    availabilityInput.checked = state.available;
    startInput.disabled = !state.available;
    endInput.disabled = !state.available;
    startOutput.textContent = orderedRangeLabelForValue(config, state.startValue);
    endOutput.textContent = orderedRangeLabelForValue(config, state.endValue);
    root.style.setProperty(
        orderedRangeStartPositionProperty,
        `${orderedRangePositionPercent(config, state.startValue)}%`,
    );
    root.style.setProperty(
        orderedRangeEndPositionProperty,
        `${orderedRangePositionPercent(config, state.endValue)}%`,
    );
}

function updateEndpoint(
    control: OrderedRangeControl,
    endpoint: OrderedRangeEndpoint,
    input: HTMLInputElement,
): void {
    const value = Number(input.value);
    try {
        control.state = orderedRangeStateForInput(control.config, control.state, endpoint, value);
        synchronizeOrderedRange(control);
    } catch (error) {
        control.report(diagnostic(
            control.root,
            "invalid-input-value",
            error instanceof Error ? error.message : String(error),
        ));
    }
}

function initializeOrderedRange(
    root: HTMLElement,
    report: OrderedRangeDiagnosticReporter,
): OrderedRangeControl | null {
    const existing = initializedControls.get(root);
    if (existing !== undefined) return existing;

    const control = readOrderedRangeControl(root, report);
    if (control === null) return null;

    control.availabilityInput.addEventListener("change", () => {
        control.state = { ...control.state, available: control.availabilityInput.checked };
        synchronizeOrderedRange(control);
    });
    control.startInput.addEventListener("input", () => {
        updateEndpoint(control, "start", control.startInput);
    });
    control.endInput.addEventListener("input", () => {
        updateEndpoint(control, "end", control.endInput);
    });

    initializedControls.set(root, control);
    synchronizeOrderedRange(control);
    return control;
}

function orderedRangeRootsWithin(target: unknown): HTMLElement[] {
    const queryRoot = rootFromTarget(target);
    const roots = Array.from(queryRoot.querySelectorAll(`[${orderedRangeRootDomAttr}]`))
        .filter((element): element is HTMLElement => element instanceof HTMLElement);
    if (queryRoot instanceof HTMLElement && queryRoot.hasAttribute(orderedRangeRootDomAttr)) {
        roots.unshift(queryRoot);
    }
    return roots;
}

export function initializeOrderedRanges(
    target: unknown,
    report: OrderedRangeDiagnosticReporter = defaultDiagnosticReporter,
): void {
    for (const root of orderedRangeRootsWithin(target)) {
        initializeOrderedRange(root, report);
    }
}

function enableOrderedRanges(): void {
    if (typeof window === "undefined") return;

    onAppPageReady((event) => {
        initializeOrderedRanges(detailTarget(event, "target"));
    });
    onHtmxLoad((event) => {
        initializeOrderedRanges(detailTarget(event, "elt"));
    });

    if (document.readyState !== "loading") {
        initializeOrderedRanges(document.body);
    }
}

enableOrderedRanges();
