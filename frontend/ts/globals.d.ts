export {};

type FlatpickrConfig = Record<string, unknown>;
type HtmxRuntime = {
    process?: (element: Element) => void;
    trigger?: (element: Element, eventName: string) => void;
};

type BootstrapRuntime = {
    Modal?: {
        getOrCreateInstance: (element: HTMLElement) => {
            show: () => void;
            hide: () => void;
        };
    };
    Tab?: {
        getOrCreateInstance: (element: HTMLElement) => {
            show: () => void;
        };
    };
};

declare global {
    interface Window {
        htmx?: HtmxRuntime;
        bootstrap?: BootstrapRuntime;
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
