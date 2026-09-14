// IHP's development live reload clears these tracked timers before reloading.
// Layout loads this development-only asset before livereload.js.
(function enableDevelopmentTimerTracking() {
    if (typeof window === "undefined") return;

    if (!Array.isArray(window.allIntervals)) {
        window.allIntervals = [];
    }
    if (!Array.isArray(window.allTimeouts)) {
        window.allTimeouts = [];
    }

    if (typeof window.unsafeSetInterval !== "function") {
        window.unsafeSetInterval = window.setInterval.bind(window);
    }
    if (typeof window.unsafeSetTimeout !== "function") {
        window.unsafeSetTimeout = window.setTimeout.bind(window);
    }

    if (window.setInterval !== trackedSetInterval) {
        window.setInterval = trackedSetInterval;
    }
    if (window.setTimeout !== trackedSetTimeout) {
        window.setTimeout = trackedSetTimeout;
    }

    if (typeof window.clearAllIntervals !== "function") {
        window.clearAllIntervals = function clearAllIntervals(): void {
            for (const intervalId of window.allIntervals ?? []) {
                window.clearInterval(intervalId);
            }
            window.allIntervals = [];
        };
    }

    if (typeof window.clearAllTimeouts !== "function") {
        window.clearAllTimeouts = function clearAllTimeouts(): void {
            for (const timeoutId of window.allTimeouts ?? []) {
                window.clearTimeout(timeoutId);
            }
            window.allTimeouts = [];
        };
    }

    function trackedSetInterval(...args: Parameters<Window["setInterval"]>): ReturnType<Window["setInterval"]> {
        const intervalId = window.unsafeSetInterval?.(...args) ?? window.setInterval(...args);
        window.allIntervals?.push(intervalId);
        return intervalId;
    }

    function trackedSetTimeout(...args: Parameters<Window["setTimeout"]>): ReturnType<Window["setTimeout"]> {
        const timeoutId = window.unsafeSetTimeout?.(...args) ?? window.setTimeout(...args);
        window.allTimeouts?.push(timeoutId);
        return timeoutId;
    }
})();
