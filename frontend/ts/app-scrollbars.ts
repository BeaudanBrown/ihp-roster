const activeClass = "app-scrollbar-active";
const hideDelayMs = 2000;

export function scrollElementFromEventTarget(target: EventTarget | null): Element {
    if (target === document || target === window || target === document.body || target === document.documentElement) {
        return document.documentElement;
    }
    if (target instanceof Element) return target;
    return document.documentElement;
}

function enableAppScrollbars(): void {
    if (typeof window === "undefined") return;

    const timers = new WeakMap<Element, number>();

    function markScrollbarActive(element: Element): void {
        element.classList.add(activeClass);

        const existingTimer = timers.get(element);
        if (existingTimer !== undefined) {
            window.clearTimeout(existingTimer);
        }

        const nextTimer = window.setTimeout(() => {
            element.classList.remove(activeClass);
            timers.delete(element);
        }, hideDelayMs);

        timers.set(element, nextTimer);
    }

    document.addEventListener("scroll", (event) => {
        markScrollbarActive(scrollElementFromEventTarget(event.target));
    }, true);
}

enableAppScrollbars();
