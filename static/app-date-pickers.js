// Keep the date/datetime picker enhancement app-local so it survives after helpers.js is removed.
(function enableDatePickers() {
    if (typeof window === 'undefined') return;

    const initializedKey = 'appDatePickerInitialized';

    function initInput(inputEl) {
        if (!(inputEl instanceof HTMLInputElement)) return;
        if (!window.flatpickr) return;
        if (inputEl.dataset[initializedKey] === 'true') return;
        if (inputEl._flatpickr) {
            inputEl.dataset[initializedKey] = 'true';
            return;
        }

        const config = inputEl.type === 'datetime-local'
            ? {
                enableTime: true,
                time_24hr: true,
                dateFormat: 'Z',
                altInput: true,
                altFormat: 'd.m.y, H:i',
            }
            : {
                altFormat: 'd.m.y',
            };

        window.flatpickr(inputEl, config);
        inputEl.dataset[initializedKey] = 'true';
    }

    function initWithin(root) {
        if (!(root instanceof Element || root instanceof Document)) return;

        if (root instanceof HTMLInputElement && (root.type === 'date' || root.type === 'datetime-local')) {
            initInput(root);
        }

        root.querySelectorAll("input[type='date'], input[type='datetime-local']").forEach(initInput);
    }

    function handleSwap(event) {
        if (event.detail && event.detail.target instanceof HTMLElement) {
            initWithin(event.detail.target);
        }
    }

    document.addEventListener('app:page-ready', function (event) {
        initWithin((event.detail && event.detail.target) || document);
    });
    document.addEventListener('htmx:afterSwap', handleSwap);
    document.addEventListener('htmx:oobAfterSwap', handleSwap);
})();
