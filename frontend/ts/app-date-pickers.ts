import { onAppPageReady } from "./shared/lifecycle";

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
            altFormat: "d.m.y, H:i",
        }
        : {
            altFormat: "d.m.y",
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

function initWithin(root: Element | Document): void {
    if (root instanceof HTMLInputElement && (root.type === "date" || root.type === "datetime-local")) {
        initInput(root);
    }

    root.querySelectorAll<HTMLInputElement>("input[type='date'], input[type='datetime-local']").forEach(initInput);
}

function rootFromPageEvent(event: Event): Element | Document {
    const detail = event instanceof CustomEvent ? event.detail as { target?: unknown } : undefined;
    return detail?.target instanceof Element || detail?.target instanceof Document ? detail.target : document;
}

function handleSwap(event: Event): void {
    const detail = event instanceof CustomEvent ? event.detail as { target?: unknown } : undefined;
    if (detail?.target instanceof HTMLElement) {
        initWithin(detail.target);
    }
}

function enableDatePickers(): void {
    if (typeof window === "undefined") return;

    onAppPageReady((event) => {
        initWithin(rootFromPageEvent(event));
    });
    document.addEventListener("htmx:afterSwap", handleSwap);
    document.addEventListener("htmx:oobAfterSwap", handleSwap);
}

enableDatePickers();
