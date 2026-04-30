(function enableShiftPreferenceWindows() {
    if (typeof window === 'undefined') return;

    function formatHour(hour) {
        const parsed = Number.parseInt(hour, 10);
        if (Number.isNaN(parsed)) return '';
        if (parsed === 0) return '12 AM';
        if (parsed < 12) return `${parsed} AM`;
        if (parsed === 12) return '12 PM';
        return `${parsed - 12} PM`;
    }

    function syncWindow(container) {
        const startInput = container.querySelector('[data-shift-preference-start]');
        const endInput = container.querySelector('[data-shift-preference-end]');
        const label = container.querySelector('[data-shift-preference-window-label]');
        if (!startInput || !endInput || !label) return;

        let startHour = Number.parseInt(startInput.value, 10);
        let endHour = Number.parseInt(endInput.value, 10);
        if (Number.isNaN(startHour) || Number.isNaN(endHour)) return;

        if (startHour > endHour) {
            const activeElement = document.activeElement;
            if (activeElement === startInput) {
                endHour = startHour;
                endInput.value = String(endHour);
            } else {
                startHour = endHour;
                startInput.value = String(startHour);
            }
        }

        label.textContent = `${formatHour(startHour)} - ${formatHour(endHour)}`;
    }

    function initShiftPreferenceWindows(target) {
        const root = target instanceof HTMLElement ? target : document;
        root.querySelectorAll('[data-shift-preference-window]').forEach(function (container) {
            if (container.dataset.shiftPreferenceWindowReady === 'true') return;
            container.dataset.shiftPreferenceWindowReady = 'true';

            const startInput = container.querySelector('[data-shift-preference-start]');
            const endInput = container.querySelector('[data-shift-preference-end]');
            [startInput, endInput].forEach(function (input) {
                if (!input) return;
                input.addEventListener('input', function () {
                    syncWindow(container);
                });
            });

            syncWindow(container);
        });
    }

    document.addEventListener('app:page-ready', function (event) {
        initShiftPreferenceWindows(event.detail && event.detail.target);
    });

    if (document.readyState !== 'loading') {
        initShiftPreferenceWindows(document.body);
    }
})();
