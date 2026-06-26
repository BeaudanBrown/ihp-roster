import { type DomRoot, closestHTMLElement, isDomRoot, isHTMLElement } from "./shared/dom";
import { detailTarget, onAppPageReady } from "./shared/lifecycle";
import {
    buildTimeOptionsWithStepForRange,
    displayLabelFromTimeValue,
    minuteOfDayFromTimeValue,
    type TimeOption,
    type TimeRange,
} from "./time-picker/options";

export { buildTimeOptionsWithStepForRange, displayLabelFromTimeValue, minuteOfDayFromTimeValue };

// Reusable quarter-hour modal time picker.
// Any field using [data-time-picker-field] + .js-time-picker-input + .js-time-picker-trigger
// can opt into this behavior.
(function enableQuarterHourTimePicker() {
    if (typeof window === "undefined") return;

    const modalId = "quarter-hour-time-picker-modal";
    const defaultEmptyLabel = "Time";
    let activeField: HTMLElement | null = null;

    function getModalElement(): HTMLElement | null {
        const modalEl = document.getElementById(modalId);
        return isHTMLElement(modalEl) ? modalEl : null;
    }

    function getBootstrapModal(modalEl: HTMLElement | null): { show: () => void; hide: () => void } | null {
        if (modalEl === null || window.bootstrap?.Modal === undefined) return null;
        return window.bootstrap.Modal.getOrCreateInstance(modalEl);
    }

    function forceHideModal(modalEl: HTMLElement | null): void {
        if (modalEl === null) return;

        modalEl.classList.remove("show");
        modalEl.style.display = "none";
        modalEl.setAttribute("aria-hidden", "true");
        modalEl.removeAttribute("aria-modal");
        document.body.classList.remove("modal-open");
        document.body.style.removeProperty("padding-right");
        document.querySelectorAll(".modal-backdrop").forEach(function (backdropEl) {
            backdropEl.remove();
        });
        activeField = null;
    }

    function hideTimePickerModal(modalEl: HTMLElement | null): void {
        if (modalEl === null) return;

        const bootstrapModal = getBootstrapModal(modalEl);
        if (bootstrapModal !== null) bootstrapModal.hide();

        window.setTimeout(function () {
            if (modalEl.classList.contains("show")) {
                forceHideModal(modalEl);
            }
        }, 150);
    }

    function getFieldInput(fieldEl: HTMLElement | null): HTMLInputElement | null {
        return fieldEl?.querySelector<HTMLInputElement>(".js-time-picker-input") ?? null;
    }

    function getFieldLabel(fieldEl: HTMLElement | null): HTMLElement | null {
        const labelEl = fieldEl?.querySelector(".js-time-picker-label") ?? null;
        return isHTMLElement(labelEl) ? labelEl : null;
    }

    function getStepDownButton(fieldEl: HTMLElement | null): HTMLButtonElement | null {
        return fieldEl?.querySelector<HTMLButtonElement>(".js-time-picker-step-down") ?? null;
    }

    function getStepUpButton(fieldEl: HTMLElement | null): HTMLButtonElement | null {
        return fieldEl?.querySelector<HTMLButtonElement>(".js-time-picker-step-up") ?? null;
    }

    function emptyLabelForField(fieldEl: HTMLElement | null): string {
        return fieldEl?.dataset.timePickerEmptyLabel || defaultEmptyLabel;
    }

    function findOptionByValue(modalEl: HTMLElement | null, value: string): HTMLElement | null {
        if (modalEl === null) return null;
        const optionEl = modalEl.querySelector(`.js-time-picker-option[data-time-value="${value}"]`);
        return isHTMLElement(optionEl) ? optionEl : null;
    }

    function resolveRange(fieldEl: HTMLElement | null, modalEl: HTMLElement | null): TimeRange | null {
        const defaultStart = modalEl?.dataset.defaultStartTime || "06:00";
        const defaultEnd = modalEl?.dataset.defaultEndTime || "23:45";
        const startValue = fieldEl?.dataset.timePickerStart || defaultStart;
        const endValue = fieldEl?.dataset.timePickerEnd || defaultEnd;

        const startMinute = minuteOfDayFromTimeValue(startValue);
        const endMinuteRaw = minuteOfDayFromTimeValue(endValue);
        if (startMinute === null || endMinuteRaw === null) return null;

        const endMinute = endMinuteRaw < startMinute ? endMinuteRaw + 24 * 60 : endMinuteRaw;
        return { startMinute, endMinute };
    }

    function stepMinutesForField(fieldEl: HTMLElement | null): number {
        const rawValue = fieldEl?.dataset.timePickerStepMinutes;
        const parsed = Number(rawValue || "15");
        if (!Number.isInteger(parsed) || parsed <= 0) return 15;
        return parsed;
    }

    function buildFieldOptions(fieldEl: HTMLElement | null, modalEl: HTMLElement | null): TimeOption[] {
        const range = resolveRange(fieldEl, modalEl);
        if (range === null) return [];
        return buildTimeOptionsWithStepForRange(range, stepMinutesForField(fieldEl));
    }

    function renderOptions(modalEl: HTMLElement | null, fieldEl: HTMLElement | null): void {
        if (modalEl === null) return;
        const gridEl = modalEl.querySelector(".js-time-picker-grid");
        if (!isHTMLElement(gridEl)) return;

        const options = buildFieldOptions(fieldEl, modalEl);
        gridEl.innerHTML = options
            .map(function (option) {
                return (
                    `<button type="button" class="btn btn-outline-secondary time-picker-option js-time-picker-option" data-time-value="${option.value}">` +
                    `${option.label}</button>`
                );
            })
            .join("");
    }

    function updateFieldLabel(fieldEl: HTMLElement | null, value: string, explicitLabel?: string): void {
        const labelEl = getFieldLabel(fieldEl);
        if (labelEl === null) return;

        if (!value) {
            labelEl.textContent = emptyLabelForField(fieldEl);
            labelEl.classList.add("app-muted");
            return;
        }

        labelEl.textContent = explicitLabel || value;
        labelEl.classList.remove("app-muted");
    }

    function highlightSelectedOption(modalEl: HTMLElement | null, value: string): void {
        if (modalEl === null) return;

        modalEl.querySelectorAll<HTMLElement>(".js-time-picker-option").forEach(function (optionEl) {
            const isSelected = value !== "" && optionEl.dataset.timeValue === value;
            optionEl.classList.toggle("active", isSelected);
            optionEl.classList.toggle("btn-primary", isSelected);
            optionEl.classList.toggle("btn-outline-secondary", !isSelected);
        });
    }

    function applyTimeValue(fieldEl: HTMLElement | null, value: string, labelText?: string): void {
        const inputEl = getFieldInput(fieldEl);
        if (inputEl === null || inputEl.disabled) return;

        const previousValue = inputEl.value || "";
        const nextValue = value || "";

        updateFieldLabel(fieldEl, nextValue, labelText);
        if (previousValue === nextValue) return;

        inputEl.value = nextValue;
        inputEl.dispatchEvent(new Event("input", { bubbles: true }));
        if (window.htmx?.trigger !== undefined) {
            window.htmx.trigger(inputEl, "change");
        } else {
            inputEl.dispatchEvent(new Event("change", { bubbles: true }));
        }
    }

    function syncFieldControls(fieldEl: HTMLElement | null): void {
        if (fieldEl === null) return;

        const inputEl = getFieldInput(fieldEl);
        if (inputEl === null) return;

        const triggerEl = fieldEl.querySelector<HTMLButtonElement>(".js-time-picker-trigger");
        const stepDownEl = getStepDownButton(fieldEl);
        const stepUpEl = getStepUpButton(fieldEl);
        const isFieldDisabled = Boolean(inputEl.disabled);
        const options = buildFieldOptions(fieldEl, getModalElement());
        const currentValue = inputEl.value || "";
        const selectedIndex = options.findIndex(function (option) {
            return option.value === currentValue;
        });
        const hasSelection = selectedIndex >= 0;

        if (triggerEl !== null) triggerEl.disabled = isFieldDisabled;
        if (stepDownEl !== null) stepDownEl.disabled = isFieldDisabled || !hasSelection || selectedIndex === 0;
        if (stepUpEl !== null) stepUpEl.disabled = isFieldDisabled || !hasSelection || selectedIndex === options.length - 1;
    }

    function stepFieldValue(fieldEl: HTMLElement | null, direction: number): void {
        if (fieldEl === null) return;

        const inputEl = getFieldInput(fieldEl);
        if (inputEl === null || inputEl.disabled) return;

        const options = buildFieldOptions(fieldEl, getModalElement());
        const currentValue = inputEl.value || "";
        const selectedIndex = options.findIndex(function (option) {
            return option.value === currentValue;
        });
        if (selectedIndex < 0) {
            syncFieldControls(fieldEl);
            return;
        }

        const nextIndex = selectedIndex + direction;
        if (nextIndex < 0 || nextIndex >= options.length) {
            syncFieldControls(fieldEl);
            return;
        }

        const nextOption = options[nextIndex];
        applyTimeValue(fieldEl, nextOption.value, nextOption.label);
        syncFieldControls(fieldEl);
    }

    document.addEventListener("click", function (event) {
        const triggerEl = closestHTMLElement(event.target, ".js-time-picker-trigger");
        if (!(triggerEl instanceof HTMLButtonElement)) return;
        if (triggerEl.disabled) return;

        const fieldEl = closestHTMLElement(triggerEl, "[data-time-picker-field]");
        const inputEl = getFieldInput(fieldEl);
        if (fieldEl === null || inputEl === null || inputEl.disabled) return;

        const modalEl = getModalElement();
        const bootstrapModal = getBootstrapModal(modalEl);
        if (modalEl === null || bootstrapModal === null) return;

        activeField = fieldEl;
        renderOptions(modalEl, fieldEl);
        highlightSelectedOption(modalEl, inputEl.value || "");
        bootstrapModal.show();
    });

    document.addEventListener("click", function (event) {
        const stepDownEl = closestHTMLElement(event.target, ".js-time-picker-step-down");
        if (!(stepDownEl instanceof HTMLButtonElement)) return;
        if (stepDownEl.disabled) return;

        const fieldEl = closestHTMLElement(stepDownEl, "[data-time-picker-field]");
        stepFieldValue(fieldEl, -1);
    });

    document.addEventListener("click", function (event) {
        const stepUpEl = closestHTMLElement(event.target, ".js-time-picker-step-up");
        if (!(stepUpEl instanceof HTMLButtonElement)) return;
        if (stepUpEl.disabled) return;

        const fieldEl = closestHTMLElement(stepUpEl, "[data-time-picker-field]");
        stepFieldValue(fieldEl, 1);
    });

    document.addEventListener("click", function (event) {
        const optionEl = closestHTMLElement(event.target, ".js-time-picker-option");
        if (optionEl === null) return;
        if (activeField === null) return;

        const modalEl = getModalElement();
        const value = optionEl.dataset.timeValue || "";
        const labelText = optionEl.textContent ? optionEl.textContent.trim() : value;

        applyTimeValue(activeField, value, labelText);
        highlightSelectedOption(modalEl, value);
        syncFieldControls(activeField);
        hideTimePickerModal(modalEl);
    });

    document.addEventListener("click", function (event) {
        const clearButton = closestHTMLElement(event.target, ".js-time-picker-clear");
        if (clearButton === null) return;
        if (activeField === null) return;

        const modalEl = getModalElement();

        applyTimeValue(activeField, "", emptyLabelForField(activeField));
        highlightSelectedOption(modalEl, "");
        syncFieldControls(activeField);
        hideTimePickerModal(modalEl);
    });

    document.addEventListener("hidden.bs.modal", function (event) {
        const modalEl = event.target;
        if (!isHTMLElement(modalEl)) return;
        if (modalEl.id !== modalId) return;

        activeField = null;
    });

    function syncFieldLabelsWithin(root: DomRoot): void {
        const fieldsToSync = new Set<HTMLElement>();

        if (root instanceof Element) {
            if (root.matches("[data-time-picker-field]") && isHTMLElement(root)) {
                fieldsToSync.add(root);
            }

            const closestField = root.closest("[data-time-picker-field]");
            if (isHTMLElement(closestField)) {
                fieldsToSync.add(closestField);
            }
        }

        root.querySelectorAll<HTMLElement>("[data-time-picker-field]").forEach(function (fieldEl) {
            fieldsToSync.add(fieldEl);
        });

        fieldsToSync.forEach(function (fieldEl) {
            const inputEl = getFieldInput(fieldEl);
            if (inputEl === null) return;
            const modalEl = getModalElement();
            const selectedOption = findOptionByValue(modalEl, inputEl.value || "");
            const selectedLabel = selectedOption?.textContent?.trim() || displayLabelFromTimeValue(inputEl.value);
            updateFieldLabel(fieldEl, inputEl.value || "", selectedLabel);
            syncFieldControls(fieldEl);
        });
    }

    function syncFieldLabelsForTarget(target: unknown): void {
        syncFieldLabelsWithin(isDomRoot(target) ? target : document);
    }

    onAppPageReady(function (event) {
        syncFieldLabelsForTarget(detailTarget(event, "target"));
    });

    document.addEventListener("time-picker:sync", function (event) {
        syncFieldLabelsForTarget(detailTarget(event, "target"));
    });
})();
