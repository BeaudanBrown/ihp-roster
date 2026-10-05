import { type DomRoot } from "./shared/dom";
import { detailRoot, onAppPageReady } from "./shared/lifecycle";

// Keep the date/datetime picker enhancement app-local so it survives after helpers.js is removed.
type FlatpickrConfig = {
    enableTime?: boolean;
    time_24hr?: boolean;
    dateFormat?: string;
    altInput?: boolean;
    altFormat?: string;
};

const initializedKey = "appDatePickerInitialized";

export function datePickerConfigFor(inputType: string): FlatpickrConfig {
    return inputType === "datetime-local"
        ? {
            enableTime: true,
            time_24hr: true,
            dateFormat: "Z",
            altInput: true,
            altFormat: "d/m/Y, H:i",
        }
        : {
            dateFormat: "Y-m-d",
            altInput: true,
            altFormat: "d/m/Y",
        };
}

export function associateDatePickerLabels(
    input: Pick<HTMLInputElement, "id">,
    display: Pick<HTMLInputElement, "id">,
    labels: readonly Pick<HTMLLabelElement, "htmlFor">[],
): void {
    if (!input.id || labels.length === 0) return;
    if (!display.id) display.id = `${input.id}-date-picker-display`;
    for (const label of labels) label.htmlFor = display.id;
}

function initInput(inputEl: HTMLInputElement): void {
    if (typeof window.flatpickr !== "function") return;
    if (inputEl.dataset[initializedKey] === "true") return;
    if (inputEl._flatpickr !== undefined) {
        inputEl.dataset[initializedKey] = "true";
        return;
    }

    // Flatpickr hides the named input. Retain its ID for the form/API while
    // associating the authored labels with the visible, focusable control.
    const labels = Array.from(inputEl.labels ?? []);
    window.flatpickr(inputEl, datePickerConfigFor(inputEl.type));
    const picker = inputEl._flatpickr as { mobileInput?: HTMLInputElement; altInput?: HTMLInputElement } | undefined;
    const display = picker?.mobileInput ?? picker?.altInput;
    if (display instanceof HTMLInputElement) associateDatePickerLabels(inputEl, display, labels);
    inputEl.dataset[initializedKey] = "true";
}

function initWithin(root: DomRoot): void {
    if (root instanceof HTMLInputElement && (root.type === "date" || root.type === "datetime-local")) {
        initInput(root);
    }

    root.querySelectorAll<HTMLInputElement>("input[type='date'], input[type='datetime-local']").forEach(initInput);
}

function handleSwap(event: Event): void {
    initWithin(detailRoot(event, "target"));
}

function enableDatePickers(): void {
    if (typeof window === "undefined") return;

    onAppPageReady((event) => {
        initWithin(detailRoot(event, "target"));
    });
    document.addEventListener("htmx:afterSwap", handleSwap);
    document.addEventListener("htmx:oobAfterSwap", handleSwap);
}

enableDatePickers();
