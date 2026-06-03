(function enableAppScrollbars() {
    if (typeof window === 'undefined') return;

    const activeClass = 'app-scrollbar-active';
    const hideDelayMs = 2000;
    const timers = new WeakMap();

    function scrollElementFromEventTarget(target) {
        if (target === document || target === window || target === document.body || target === document.documentElement) {
            return document.documentElement;
        }
        if (target instanceof Element) return target;
        return document.documentElement;
    }

    function markScrollbarActive(element) {
        if (!(element instanceof Element)) return;

        element.classList.add(activeClass);

        const existingTimer = timers.get(element);
        if (existingTimer) {
            window.clearTimeout(existingTimer);
        }

        const nextTimer = window.setTimeout(function () {
            element.classList.remove(activeClass);
            timers.delete(element);
        }, hideDelayMs);

        timers.set(element, nextTimer);
    }

    document.addEventListener('scroll', function (event) {
        markScrollbarActive(scrollElementFromEventTarget(event.target));
    }, true);
})();
