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

function initInput(inputEl: HTMLInputElement): void {
    if (typeof window.flatpickr !== "function") return;
    if (inputEl.dataset[initializedKey] === "true") return;
    if (inputEl._flatpickr !== undefined) {
        inputEl.dataset[initializedKey] = "true";
        return;
    }

    window.flatpickr(inputEl, datePickerConfigFor(inputEl.type));
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
