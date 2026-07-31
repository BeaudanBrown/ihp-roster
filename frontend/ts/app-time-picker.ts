import {
    timePickerClearDomAttr,
    timePickerConfigDomAttr,
    timePickerFieldDomAttr,
    timePickerKeyboardDomAttr,
    timePickerLabelDomAttr,
    timePickerModalDomId,
    timePickerOptionDomAttr,
    timePickerOptionsDomAttr,
    timePickerStepDownDomAttr,
    timePickerStepUpDomAttr,
    timePickerTriggerDomAttr,
    timePickerValueDomAttr,
    type TimePickerConfig,
    type TimePickerOption,
} from "./generated/contracts";
import { closestHTMLElement, isHTMLElement, rootFromTarget } from "./shared/dom";
import { detailTarget, onAppPageReady, onHtmxLoad } from "./shared/lifecycle";
import {
    parseTimePickerConfiguration,
    parseTimePickerOptionConfiguration,
    timePickerOptionsForConfiguration,
} from "./time-picker/configuration";
import { steppedTimePickerOption, wholeHourTimePickerOption, type TimePickerStepDirection } from "./time-picker/keyboard";

export type TimePickerDiagnosticCode =
    | "invalid-modal"
    | "invalid-option"
    | "invalid-field-config"
    | "invalid-field-structure"
    | "invalid-field-value";

export type TimePickerDiagnostic = {
    code: TimePickerDiagnosticCode;
    fieldName: string | null;
    message: string;
};

export type TimePickerDiagnosticReporter = (diagnostic: TimePickerDiagnostic) => void;

type TimePickerRenderedOption = {
    element: HTMLButtonElement;
    config: TimePickerOption;
};

type TimePickerModalControl = {
    modal: HTMLElement;
    grid: HTMLElement;
    clear: HTMLButtonElement;
    options: ReadonlyArray<TimePickerRenderedOption>;
    optionByElement: ReadonlyMap<HTMLButtonElement, TimePickerRenderedOption>;
};

type TimePickerFieldControl = {
    field: HTMLElement;
    input: HTMLInputElement;
    trigger: HTMLButtonElement;
    label: HTMLElement;
    stepDown: HTMLButtonElement | null;
    stepUp: HTMLButtonElement | null;
    config: TimePickerConfig;
    options: ReadonlyArray<TimePickerRenderedOption>;
    allOptionsByValue: ReadonlyMap<string, TimePickerRenderedOption>;
    keyboardEnabled: boolean;
};

type TimePickerDigitBuffer = {
    digits: string;
    lastTypedAt: number;
};

const modalControls = new WeakMap<HTMLElement, TimePickerModalControl>();
const fieldControls = new WeakMap<HTMLElement, TimePickerFieldControl>();
const digitBuffers = new WeakMap<HTMLInputElement, TimePickerDigitBuffer>();
const digitBufferResetMs = 2000;
let activeField: TimePickerFieldControl | null = null;

function defaultDiagnosticReporter(diagnostic: TimePickerDiagnostic): void {
    console.error?.("Invalid generated time picker configuration", diagnostic);
}

function reportError(
    report: TimePickerDiagnosticReporter,
    code: TimePickerDiagnosticCode,
    fieldName: string | null,
    error: unknown,
): void {
    report({
        code,
        fieldName,
        message: error instanceof Error ? error.message : String(error),
    });
}

function getModalElement(): HTMLElement | null {
    const modal = document.getElementById(timePickerModalDomId);
    return isHTMLElement(modal) ? modal : null;
}

function getBootstrapModal(modal: HTMLElement | null): { show: () => void; hide: () => void } | null {
    if (modal === null || window.bootstrap?.Modal === undefined) return null;
    return window.bootstrap.Modal.getOrCreateInstance(modal);
}

function roleElements(root: ParentNode, attribute: string): Element[] {
    return Array.from(root.querySelectorAll(`[${attribute}]`));
}

function singleRoleElement(root: ParentNode, attribute: string): Element | null {
    const elements = roleElements(root, attribute);
    return elements.length === 1 ? elements[0] : null;
}

function readModalControl(report: TimePickerDiagnosticReporter): TimePickerModalControl | null {
    const modal = getModalElement();
    if (modal === null) {
        reportError(report, "invalid-modal", null, new Error(`Missing #${timePickerModalDomId}`));
        return null;
    }
    const existing = modalControls.get(modal);
    if (existing !== undefined) return existing;

    const grid = singleRoleElement(modal, timePickerOptionsDomAttr);
    const clear = singleRoleElement(modal, timePickerClearDomAttr);
    if (!(grid instanceof HTMLElement) || !(clear instanceof HTMLButtonElement)) {
        reportError(report, "invalid-modal", null, new Error("Time picker modal must contain one generated options grid and clear button"));
        return null;
    }

    const renderedOptions: TimePickerRenderedOption[] = [];
    const optionByElement = new Map<HTMLButtonElement, TimePickerRenderedOption>();
    try {
        for (const element of roleElements(grid, timePickerOptionDomAttr)) {
            if (!(element instanceof HTMLButtonElement)) {
                throw new Error("Time picker option role must belong to a button");
            }
            const rawConfig = element.getAttribute(timePickerOptionDomAttr);
            if (rawConfig === null) throw new Error(`Missing ${timePickerOptionDomAttr}`);
            const config = parseTimePickerOptionConfiguration(rawConfig);
            if (element.textContent?.trim() !== config.label) {
                throw new Error(`Time picker option ${config.value} label disagrees with rendered copy`);
            }
            const rendered = { element, config };
            renderedOptions.push(rendered);
            optionByElement.set(element, rendered);
        }
        if (renderedOptions.length === 0) {
            throw new Error("Time picker modal must render at least one generated option");
        }
        const optionValues = new Set(renderedOptions.map((option) => option.config.value));
        if (optionValues.size !== renderedOptions.length) {
            throw new Error("Time picker modal option values must be unique");
        }
    } catch (error) {
        reportError(report, "invalid-option", null, error);
        return null;
    }

    const control = { modal, grid, clear, options: renderedOptions, optionByElement };
    modalControls.set(modal, control);
    return control;
}

function getOptionalButton(field: HTMLElement, attribute: string): HTMLButtonElement | null | undefined {
    const elements = roleElements(field, attribute);
    if (elements.length === 0) return null;
    if (elements.length === 1 && elements[0] instanceof HTMLButtonElement) return elements[0];
    return undefined;
}

function readFieldControl(
    field: HTMLElement,
    modal: TimePickerModalControl,
    report: TimePickerDiagnosticReporter,
): TimePickerFieldControl | null {
    const existing = fieldControls.get(field);
    if (existing !== undefined) return existing;

    const rawConfig = field.getAttribute(timePickerConfigDomAttr);
    let config: TimePickerConfig;
    try {
        if (rawConfig === null) throw new Error(`Missing ${timePickerConfigDomAttr}`);
        config = parseTimePickerConfiguration(rawConfig);
    } catch (error) {
        reportError(report, "invalid-field-config", null, error);
        return null;
    }

    const input = singleRoleElement(field, timePickerValueDomAttr);
    const trigger = singleRoleElement(field, timePickerTriggerDomAttr);
    const label = singleRoleElement(field, timePickerLabelDomAttr);
    const stepDown = getOptionalButton(field, timePickerStepDownDomAttr);
    const stepUp = getOptionalButton(field, timePickerStepUpDomAttr);
    const fieldName = input instanceof HTMLInputElement && input.name.length > 0 ? input.name : null;

    if (
        !(input instanceof HTMLInputElement)
        || input.type !== "hidden"
        || input.name.length === 0
        || !(trigger instanceof HTMLButtonElement)
        || !(label instanceof HTMLElement)
        || !trigger.contains(label)
        || stepDown === undefined
        || stepUp === undefined
        || (stepDown === null) !== (stepUp === null)
    ) {
        reportError(
            report,
            "invalid-field-structure",
            fieldName,
            new Error("Time picker field must contain one named hidden value, trigger/label pair, and either both or neither step buttons"),
        );
        return null;
    }

    let selectedConfigs: TimePickerOption[];
    try {
        selectedConfigs = timePickerOptionsForConfiguration(config, modal.options.map((option) => option.config));
    } catch (error) {
        reportError(report, "invalid-field-config", fieldName, error);
        return null;
    }

    const allOptionsByValue = new Map(modal.options.map((option) => [option.config.value, option]));
    const selectedOptions: TimePickerRenderedOption[] = [];
    for (const option of selectedConfigs) {
        const renderedOption = allOptionsByValue.get(option.value);
        if (renderedOption === undefined) {
            reportError(report, "invalid-field-config", fieldName, new Error("Time picker field resolved an option outside the rendered inventory"));
            return null;
        }
        selectedOptions.push(renderedOption);
    }
    if (input.value !== "" && !allOptionsByValue.has(input.value)) {
        reportError(report, "invalid-field-value", fieldName, new Error(`Time picker value ${input.value} has no Haskell-rendered option`));
        return null;
    }

    const control: TimePickerFieldControl = {
        field,
        input,
        trigger,
        label,
        stepDown,
        stepUp,
        config,
        options: selectedOptions,
        allOptionsByValue,
        keyboardEnabled: trigger.hasAttribute(timePickerKeyboardDomAttr),
    };
    fieldControls.set(field, control);
    return control;
}

function labelForValue(control: TimePickerFieldControl, value: string): string | null {
    if (value === "") return control.config.emptyLabel;
    return control.allOptionsByValue.get(value)?.config.label ?? null;
}

function synchronizeField(control: TimePickerFieldControl): void {
    const currentValue = control.input.value;
    const label = labelForValue(control, currentValue);
    if (label !== null) {
        control.label.textContent = label;
        control.label.classList.toggle("app-muted", currentValue === "");
    }

    const selectedIndex = control.options.findIndex((option) => option.config.value === currentValue);
    const hasSelection = selectedIndex >= 0;
    control.trigger.disabled = control.input.disabled;
    if (control.stepDown !== null) {
        control.stepDown.disabled = control.input.disabled || !hasSelection || selectedIndex === 0;
    }
    if (control.stepUp !== null) {
        control.stepUp.disabled = control.input.disabled || !hasSelection || selectedIndex === control.options.length - 1;
    }
}

function applyTimeValue(control: TimePickerFieldControl, value: string, label: string): void {
    if (control.input.disabled) return;

    const previousValue = control.input.value;
    control.label.textContent = label;
    control.label.classList.toggle("app-muted", value === "");
    if (previousValue === value) return;

    control.input.value = value;
    control.input.dispatchEvent(new Event("input", { bubbles: true }));
    if (window.htmx?.trigger !== undefined) {
        window.htmx.trigger(control.input, "change");
    } else {
        control.input.dispatchEvent(new Event("change", { bubbles: true }));
    }
}

function renderFieldOptions(modal: TimePickerModalControl, field: TimePickerFieldControl): void {
    modal.grid.replaceChildren(...field.options.map((option) => option.element));
}

function restoreModalOptions(modal: TimePickerModalControl): void {
    modal.grid.replaceChildren(...modal.options.map((option) => option.element));
}

function highlightSelectedOption(modal: TimePickerModalControl, value: string): void {
    for (const option of modal.options) {
        const selected = value !== "" && option.config.value === value;
        option.element.classList.toggle("active", selected);
        option.element.classList.toggle("btn-primary", selected);
        option.element.classList.toggle("btn-outline-secondary", !selected);
    }
}

function forceHideModal(modal: TimePickerModalControl): void {
    modal.modal.classList.remove("show");
    modal.modal.style.display = "none";
    modal.modal.setAttribute("aria-hidden", "true");
    modal.modal.removeAttribute("aria-modal");
    document.body.classList.remove("modal-open");
    document.body.style.removeProperty("padding-right");
    document.querySelectorAll(".modal-backdrop").forEach((backdrop) => backdrop.remove());
    restoreModalOptions(modal);
    activeField = null;
}

function hideTimePickerModal(modal: TimePickerModalControl): void {
    const bootstrapModal = getBootstrapModal(modal.modal);
    if (bootstrapModal === null) {
        forceHideModal(modal);
        modal.modal.dispatchEvent(new CustomEvent("hidden.bs.modal", { bubbles: true }));
        return;
    }

    const hideAfterShown = () => getBootstrapModal(modal.modal)?.hide();
    const removePendingHide = () => modal.modal.removeEventListener("shown.bs.modal", hideAfterShown);
    modal.modal.addEventListener("shown.bs.modal", hideAfterShown, { once: true });
    modal.modal.addEventListener("hidden.bs.modal", removePendingHide, { once: true });
    bootstrapModal.hide();
}

function stepFieldValue(control: TimePickerFieldControl, direction: TimePickerStepDirection, wrap: boolean): void {
    if (control.input.disabled) return;
    const option = wrap
        ? steppedTimePickerOption(control.options.map((candidate) => candidate.config), control.input.value, direction)
        : (() => {
            const selectedIndex = control.options.findIndex((candidate) => candidate.config.value === control.input.value);
            return selectedIndex < 0 ? null : control.options[selectedIndex + direction]?.config ?? null;
        })();
    if (option === null) {
        synchronizeField(control);
        return;
    }
    applyTimeValue(control, option.value, option.label);
    synchronizeField(control);
}

function applyWholeHourDigit(control: TimePickerFieldControl, digit: string, now: number): void {
    const previous = digitBuffers.get(control.input);
    const digits = previous === undefined || now - previous.lastTypedAt > digitBufferResetMs
        ? digit
        : previous.digits.length >= 2
            ? previous.digits
            : previous.digits + digit;
    digitBuffers.set(control.input, { digits, lastTypedAt: now });
    if (previous !== undefined && now - previous.lastTypedAt <= digitBufferResetMs && previous.digits.length >= 2) return;

    const option = wholeHourTimePickerOption(control.options.map((candidate) => candidate.config), digits);
    if (option === null) return;
    applyTimeValue(control, option.value, option.label);
    synchronizeField(control);
}

function movePickerHighlight(modal: TimePickerModalControl, control: TimePickerFieldControl, direction: TimePickerStepDirection): void {
    const activeValue = control.options.find((option) => option.element.classList.contains("active"))?.config.value ?? control.input.value;
    const option = steppedTimePickerOption(control.options.map((candidate) => candidate.config), activeValue, direction);
    if (option === null) return;
    highlightSelectedOption(modal, option.value);
    control.allOptionsByValue.get(option.value)?.element.scrollIntoView({ block: "nearest" });
}

function selectHighlightedPickerOption(modal: TimePickerModalControl, control: TimePickerFieldControl): void {
    const option = control.options.find((candidate) => candidate.element.classList.contains("active"));
    if (option === undefined) return;
    applyTimeValue(control, option.config.value, option.config.label);
    synchronizeField(control);
    hideTimePickerModal(modal);
}

function fieldFromTarget(
    target: unknown,
    modal: TimePickerModalControl,
    report: TimePickerDiagnosticReporter,
): TimePickerFieldControl | null {
    const field = closestHTMLElement(target, `[${timePickerFieldDomAttr}]`);
    return field === null ? null : readFieldControl(field, modal, report);
}

function timePickerFieldsWithin(target: unknown): HTMLElement[] {
    const root = rootFromTarget(target);
    const fields = Array.from(root.querySelectorAll(`[${timePickerFieldDomAttr}]`)).filter(isHTMLElement);
    if (root instanceof HTMLElement && root.hasAttribute(timePickerFieldDomAttr)) fields.unshift(root);
    return fields;
}

export function initializeTimePickerFields(
    target: unknown,
    report: TimePickerDiagnosticReporter = defaultDiagnosticReporter,
): void {
    const fields = timePickerFieldsWithin(target);
    if (fields.length === 0) return;
    const modal = readModalControl(report);
    if (modal === null) return;

    for (const field of fields) {
        const control = readFieldControl(field, modal, report);
        if (control !== null) synchronizeField(control);
    }
}

function enableQuarterHourTimePicker(): void {
    if (typeof window === "undefined") return;

    // The picker is a separate overlay lane above workflow dialogs. Consume
    // picker keys in capture phase before the dialog adapter can act beneath it.
    document.addEventListener("keydown", (event) => {
        const modalElement = getModalElement();
        if (modalElement === null || !modalElement.classList.contains("show")) return;
        const modal = readModalControl(defaultDiagnosticReporter);
        if (modal === null) return;

        if (event.key === "Escape") {
            event.preventDefault();
            event.stopImmediatePropagation();
            hideTimePickerModal(modal);
            return;
        }
        if (activeField === null || !activeField.keyboardEnabled) return;

        const direction: TimePickerStepDirection | null = event.key === "ArrowUp" || event.key === "ArrowRight"
            ? 1
            : event.key === "ArrowDown" || event.key === "ArrowLeft"
                ? -1
                : null;
        if (direction !== null) {
            event.preventDefault();
            event.stopImmediatePropagation();
            movePickerHighlight(modal, activeField, direction);
            return;
        }
        if (event.key === "Enter") {
            event.preventDefault();
            event.stopImmediatePropagation();
            selectHighlightedPickerOption(modal, activeField);
        }
    }, true);

    document.addEventListener("keydown", (event) => {
        const trigger = closestHTMLElement(event.target, `[${timePickerTriggerDomAttr}]`);
        if (!(trigger instanceof HTMLButtonElement) || trigger.disabled) return;
        const modal = readModalControl(defaultDiagnosticReporter);
        if (modal === null) return;
        const field = fieldFromTarget(trigger, modal, defaultDiagnosticReporter);
        if (field === null || !field.keyboardEnabled || field.input.disabled) return;

        const direction: TimePickerStepDirection | null = event.key === "ArrowUp" || event.key === "ArrowRight"
            ? 1
            : event.key === "ArrowDown" || event.key === "ArrowLeft"
                ? -1
                : null;
        if (direction !== null) {
            event.preventDefault();
            digitBuffers.delete(field.input);
            stepFieldValue(field, direction, true);
            return;
        }
        if (/^\d$/.test(event.key)) {
            event.preventDefault();
            applyWholeHourDigit(field, event.key, Date.now());
        }
    });

    document.addEventListener("click", (event) => {
        const trigger = closestHTMLElement(event.target, `[${timePickerTriggerDomAttr}]`);
        if (!(trigger instanceof HTMLButtonElement) || trigger.disabled) return;
        const modal = readModalControl(defaultDiagnosticReporter);
        if (modal === null) return;
        const field = fieldFromTarget(trigger, modal, defaultDiagnosticReporter);
        const bootstrapModal = getBootstrapModal(modal.modal);
        if (field === null || field.input.disabled || bootstrapModal === null) return;

        activeField = field;
        renderFieldOptions(modal, field);
        highlightSelectedOption(modal, field.input.value);
        bootstrapModal.show();
    });

    document.addEventListener("click", (event) => {
        const stepDown = closestHTMLElement(event.target, `[${timePickerStepDownDomAttr}]`);
        if (!(stepDown instanceof HTMLButtonElement) || stepDown.disabled) return;
        const modal = readModalControl(defaultDiagnosticReporter);
        if (modal === null) return;
        const field = fieldFromTarget(stepDown, modal, defaultDiagnosticReporter);
        if (field !== null) stepFieldValue(field, -1, false);
    });

    document.addEventListener("click", (event) => {
        const stepUp = closestHTMLElement(event.target, `[${timePickerStepUpDomAttr}]`);
        if (!(stepUp instanceof HTMLButtonElement) || stepUp.disabled) return;
        const modal = readModalControl(defaultDiagnosticReporter);
        if (modal === null) return;
        const field = fieldFromTarget(stepUp, modal, defaultDiagnosticReporter);
        if (field !== null) stepFieldValue(field, 1, false);
    });

    document.addEventListener("click", (event) => {
        const optionElement = closestHTMLElement(event.target, `[${timePickerOptionDomAttr}]`);
        if (!(optionElement instanceof HTMLButtonElement) || activeField === null) return;
        const modal = readModalControl(defaultDiagnosticReporter);
        if (modal === null) return;
        const renderedOption = modal.optionByElement.get(optionElement);
        if (renderedOption === undefined || !modal.grid.contains(optionElement)) return;

        try {
            const rawConfig = optionElement.getAttribute(timePickerOptionDomAttr);
            if (rawConfig === null) throw new Error(`Missing ${timePickerOptionDomAttr}`);
            const currentConfig = parseTimePickerOptionConfiguration(rawConfig);
            if (currentConfig.value !== renderedOption.config.value || currentConfig.label !== renderedOption.config.label) {
                throw new Error("Time picker option payload changed after initialization");
            }
        } catch (error) {
            reportError(defaultDiagnosticReporter, "invalid-option", activeField.input.name, error);
            return;
        }

        applyTimeValue(activeField, renderedOption.config.value, renderedOption.config.label);
        highlightSelectedOption(modal, renderedOption.config.value);
        synchronizeField(activeField);
        hideTimePickerModal(modal);
    });

    document.addEventListener("click", (event) => {
        const clear = closestHTMLElement(event.target, `[${timePickerClearDomAttr}]`);
        if (!(clear instanceof HTMLButtonElement) || activeField === null) return;
        const modal = readModalControl(defaultDiagnosticReporter);
        if (modal === null || clear !== modal.clear) return;

        applyTimeValue(activeField, "", activeField.config.emptyLabel);
        highlightSelectedOption(modal, "");
        synchronizeField(activeField);
        hideTimePickerModal(modal);
    });

    document.addEventListener("hidden.bs.modal", (event) => {
        if (!(event.target instanceof HTMLElement) || event.target.id !== timePickerModalDomId) return;
        const modal = modalControls.get(event.target);
        if (modal !== undefined) restoreModalOptions(modal);
        activeField = null;
    });

    onAppPageReady((event) => {
        initializeTimePickerFields(detailTarget(event, "target"));
    });
    onHtmxLoad((event) => {
        initializeTimePickerFields(detailTarget(event, "elt"));
    });

    if (document.readyState !== "loading") {
        initializeTimePickerFields(document.body);
    }
}

enableQuarterHourTimePicker();
