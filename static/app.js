$(document).on('ready turbolinks:load', function () {
    // This is called on the first page load and also when the page is changed by turbolinks.
    if (window.htmx && typeof window.htmx.process === 'function') {
        window.htmx.process(document.body);
    }
});

(function enableDialogOverlayMount() {
    if (typeof window === 'undefined') return;

    const mountId = 'dialog-overlay-mount';
    let lastTrigger = null;

    function getMount() {
        return document.getElementById(mountId);
    }

    function getActiveDialog() {
        const mountEl = getMount();
        return mountEl ? mountEl.querySelector('[data-dialog-overlay="true"]') : null;
    }

    function hasVisibleBootstrapModal() {
        return Boolean(document.querySelector('.modal.show:not([data-dialog-overlay="true"])'));
    }

    function focusDialog(dialogEl) {
        if (!(dialogEl instanceof HTMLElement)) return;

        const focusTarget = dialogEl.querySelector('[autofocus], .is-invalid, input, select, textarea, button, a[href]');
        if (focusTarget instanceof HTMLElement) {
            focusTarget.focus();
            return;
        }

        dialogEl.focus();
    }

    function restoreFocus() {
        if (lastTrigger instanceof HTMLElement && document.contains(lastTrigger)) {
            lastTrigger.focus();
        }
        lastTrigger = null;
    }

    function syncDialogState() {
        const dialogEl = getActiveDialog();
        const hasDialog = dialogEl instanceof HTMLElement;
        const shouldLockBody = hasDialog || hasVisibleBootstrapModal();

        document.body.classList.toggle('modal-open', shouldLockBody);
        document.body.style.overflow = shouldLockBody ? 'hidden' : '';

        if (hasDialog) {
            focusDialog(dialogEl);
        } else if (!hasVisibleBootstrapModal()) {
            restoreFocus();
        }
    }

    function clearMount() {
        const mountEl = getMount();
        if (!(mountEl instanceof HTMLElement)) return;

        mountEl.innerHTML = '';
        syncDialogState();
    }

    document.addEventListener('click', function (event) {
        const triggerEl = event.target.closest(`[hx-target="#${mountId}"]`);
        if (triggerEl instanceof HTMLElement) {
            lastTrigger = triggerEl;
        }
    }, true);

    document.addEventListener('click', function (event) {
        const activeDialog = getActiveDialog();
        const closeEl = event.target.closest('[data-dialog-overlay-close="true"]');
        if (closeEl && activeDialog) {
            event.preventDefault();
            clearMount();
            return;
        }

        const backdropEl = event.target.closest('[data-dialog-overlay-backdrop="true"]');
        if (backdropEl && activeDialog) {
            event.preventDefault();
            clearMount();
            return;
        }

        if (activeDialog && event.target === activeDialog) {
            event.preventDefault();
            clearMount();
        }
    });

    document.addEventListener('keydown', function (event) {
        if (event.key !== 'Escape') return;
        if (!getActiveDialog()) return;

        event.preventDefault();
        clearMount();
    });

    document.addEventListener('htmx:afterSwap', function (event) {
        if (!(event.detail && event.detail.target instanceof HTMLElement)) return;
        if (event.detail.target.id !== mountId) return;

        if (window.htmx && typeof window.htmx.process === 'function') {
            window.htmx.process(event.detail.target);
        }

        syncDialogState();
    });

    document.addEventListener('shown.bs.modal', syncDialogState);
    document.addEventListener('hidden.bs.modal', syncDialogState);
    document.addEventListener('turbolinks:load', syncDialogState);

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', syncDialogState);
    } else {
        syncDialogState();
    }
})();

(function enableToastOverlayHost() {
    if (typeof window === 'undefined') return;

    const hostId = 'toast-overlay-mount';
    const initializedKey = 'toastInitialized';

    function getHost() {
        return document.getElementById(hostId);
    }

    function dismissToast(toastEl) {
        if (!(toastEl instanceof HTMLElement)) return;
        toastEl.classList.add('app-toast-leaving');
        window.setTimeout(function () {
            if (toastEl.parentNode) {
                toastEl.remove();
            }
        }, 220);
    }

    function initToast(toastEl) {
        if (!(toastEl instanceof HTMLElement)) return;
        if (toastEl.dataset[initializedKey] === 'true') return;

        toastEl.dataset[initializedKey] = 'true';
        const autoHideMs = Number.parseInt(toastEl.dataset.autoHideMs || '0', 10);
        if (autoHideMs > 0) {
            window.setTimeout(function () {
                dismissToast(toastEl);
            }, autoHideMs);
        }
    }

    function initHostToasts() {
        const hostEl = getHost();
        if (!(hostEl instanceof HTMLElement)) return;
        hostEl.querySelectorAll('[data-overlay-toast="true"]').forEach(initToast);
    }

    document.addEventListener('click', function (event) {
        const closeEl = event.target.closest('[data-toast-close="true"]');
        if (!(closeEl instanceof HTMLElement)) return;

        const toastEl = closeEl.closest('[data-overlay-toast="true"]');
        if (toastEl instanceof HTMLElement) {
            dismissToast(toastEl);
        }
    });

    document.addEventListener('htmx:afterSwap', initHostToasts);
    document.addEventListener('htmx:oobAfterSwap', initHostToasts);
    document.addEventListener('turbolinks:load', initHostToasts);

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initHostToasts);
    } else {
        initHostToasts();
    }
})();
