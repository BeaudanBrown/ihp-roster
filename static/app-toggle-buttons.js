(function enableAppToggleButtons() {
    if (typeof window === 'undefined') return;

    function syncHiddenInput(input) {
        const hiddenInputId = input.dataset.appToggleHiddenInputId;
        if (!hiddenInputId) return;

        const hiddenInput = document.getElementById(hiddenInputId);
        if (!hiddenInput) return;

        const checkedValue = input.dataset.appToggleHiddenCheckedValue || 'true';
        const uncheckedValue = input.dataset.appToggleHiddenUncheckedValue || 'false';
        hiddenInput.value = input.checked ? checkedValue : uncheckedValue;
    }

    function syncToggleButton(input) {
        const button = input.closest('[data-app-toggle-button]');
        if (!button) return;

        button.classList.toggle('btn-success', input.checked);
        button.classList.toggle('btn-outline-success', !input.checked);
        button.setAttribute('aria-pressed', input.checked ? 'true' : 'false');
        if (input.getAttribute('role') === 'switch') {
            input.setAttribute('aria-checked', input.checked ? 'true' : 'false');
        }
        syncHiddenInput(input);
    }

    function initToggleButtons(target) {
        const root = target instanceof Element || target instanceof Document ? target : document;
        root.querySelectorAll('[data-app-toggle-button-input="true"]').forEach(function (input) {
            if (input.dataset.appToggleButtonReady === 'true') return;
            input.dataset.appToggleButtonReady = 'true';
            input.addEventListener('change', function () {
                syncToggleButton(input);
            });
            syncToggleButton(input);
        });
    }

    document.addEventListener('app:page-ready', function (event) {
        initToggleButtons((event.detail && event.detail.target) || document);
    });
    document.addEventListener('htmx:load', function (event) {
        initToggleButtons((event.detail && event.detail.elt) || document);
    });

    if (document.readyState !== 'loading') {
        initToggleButtons(document.body);
    }
})();
