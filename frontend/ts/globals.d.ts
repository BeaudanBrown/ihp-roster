export {};

type FlatpickrConfig = Record<string, unknown>;

declare global {
    interface Window {
        htmx?: unknown;
        bootstrap?: unknown;
        flatpickr?: (element: HTMLInputElement, config: FlatpickrConfig) => unknown;
    }

    interface HTMLInputElement {
        _flatpickr?: unknown;
    }
}
