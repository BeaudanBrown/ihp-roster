export {};

type FlatpickrConfig = Record<string, unknown>;
type HtmxRuntime = {
    process?: (element: Element) => void;
};

declare global {
    interface Window {
        htmx?: HtmxRuntime;
        bootstrap?: unknown;
        appPageLifecycle?: {
            eventName: string;
            dispatchPageReady: (detail?: unknown) => void;
        };
        allIntervals?: number[];
        allTimeouts?: number[];
        unsafeSetInterval?: Window["setInterval"];
        unsafeSetTimeout?: Window["setTimeout"];
        clearAllIntervals?: () => void;
        clearAllTimeouts?: () => void;
        flatpickr?: (element: HTMLInputElement, config: FlatpickrConfig) => unknown;
    }

    interface HTMLInputElement {
        _flatpickr?: unknown;
    }
}
