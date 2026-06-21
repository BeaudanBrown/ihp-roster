// @ts-nocheck
export function dialogSubmitLoadingHtml(label) {
    return '<span class="spinner-border spinner-border-sm" aria-hidden="true"></span><span>' + label + '</span>';
}

// Shared workflow dialog mount for HTMX-driven form overlays.
(function enableDialogOverlayMount() {
    if (typeof window === 'undefined') return;

    const mountId = 'dialog-overlay-mount';
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

    function syncDialogState() {
        const dialogEl = getActiveDialog();
        const hasDialog = dialogEl instanceof HTMLElement;
        const shouldLockBody = hasDialog || hasVisibleBootstrapModal();

        document.body.classList.toggle('modal-open', shouldLockBody);
        document.body.style.overflow = shouldLockBody ? 'hidden' : '';
    }

    function clearMount() {
        const mountEl = getMount();
        if (!(mountEl instanceof HTMLElement)) return;

        mountEl.innerHTML = '';
        syncDialogState();
    }

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

        // The full-screen dialog shell sits above the backdrop, so background clicks
        // often land on the shell instead of the separate backdrop node.
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

    document.addEventListener('submit', function (event) {
        const activeDialog = getActiveDialog();
        if (!activeDialog) return;

        const form = event.target;
        if (!(form instanceof HTMLFormElement)) return;

        const submitter = event.submitter;
        if (!(submitter instanceof HTMLButtonElement)) return;
        if (!submitter.matches('[data-dialog-overlay-submit-button="true"]')) return;

        activeDialog.querySelectorAll('button, a.btn').forEach(function (control) {
            if (control instanceof HTMLButtonElement) {
                control.disabled = true;
            } else {
                control.classList.add('disabled');
                control.setAttribute('aria-disabled', 'true');
            }
        });

        if (!submitter.dataset.originalHtml) {
            submitter.dataset.originalHtml = submitter.innerHTML;
        }
        const label = submitter.getAttribute('data-loading-label') || 'Working...';
        submitter.innerHTML = dialogSubmitLoadingHtml(label);
        submitter.classList.add('d-inline-flex', 'align-items-center', 'gap-2');
    }, true);

    document.addEventListener('htmx:afterRequest', function (event) {
        const activeDialog = getActiveDialog();
        if (!activeDialog) return;
        if (!(event.detail && event.detail.elt instanceof HTMLElement)) return;
        if (!activeDialog.contains(event.detail.elt)) return;

        activeDialog.querySelectorAll('button, a.btn').forEach(function (control) {
            if (control instanceof HTMLButtonElement) {
                control.disabled = false;
            } else {
                control.classList.remove('disabled');
                control.removeAttribute('aria-disabled');
            }
        });

        activeDialog.querySelectorAll('[data-dialog-overlay-submit-button="true"]').forEach(function (control) {
            if (!(control instanceof HTMLButtonElement)) return;
            if (control.dataset.originalHtml) {
                control.innerHTML = control.dataset.originalHtml;
            }
            control.classList.remove('d-inline-flex', 'align-items-center', 'gap-2');
        });
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
    document.addEventListener('app:page-ready', syncDialogState);
})();
