// Toggle break-time controls based on the "Had break" checkbox.
(function enableBreakTimeToggle() {
    if (typeof window === 'undefined') return;

    function syncBreakToggle(checkboxEl) {
        const targetSelector = checkboxEl.dataset.breakTarget;
        if (!targetSelector) return;

        const targetEl = document.querySelector(targetSelector);
        if (!targetEl) return;

        const isEnabled = checkboxEl.checked;
        targetEl.hidden = !isEnabled;
        targetEl.querySelectorAll('.js-time-picker-input, .js-time-picker-trigger, .js-time-picker-step-down, .js-time-picker-step-up').forEach(function (element) {
            element.disabled = !isEnabled;
        });
        document.dispatchEvent(new CustomEvent('time-picker:sync', { detail: { target: targetEl } }));
    }

    document.addEventListener('change', function (event) {
        const checkboxEl = event.target.closest('[data-break-toggle="true"]');
        if (!checkboxEl) return;
        syncBreakToggle(checkboxEl);
    });

    function syncAllBreakTogglesWithin(root) {
        if (!(root instanceof Element || root instanceof Document)) return;

        root.querySelectorAll('[data-break-toggle="true"]').forEach(function (checkboxEl) {
            syncBreakToggle(checkboxEl);
        });
    }

    document.addEventListener('app:page-ready', function (event) {
        syncAllBreakTogglesWithin((event.detail && event.detail.target) || document);
    });
})();

(function enableTimesheetDayColumnDragScroll() {
    if (typeof window === 'undefined') return;

    const dayColumnLayoutSelector = '.timesheet-week-frame[data-timesheet-layout="day_columns"]';
    const dragThreshold = 6;
    const clickSuppressionMs = 250;

    let dragState = null;
    let suppressedClickState = null;

    function findTimesheetFrame(target) {
        if (!(target instanceof Element)) return null;
        return target.closest(dayColumnLayoutSelector);
    }

    function clearSuppressedClickState() {
        if (suppressedClickState && suppressedClickState.timeoutId) {
            window.clearTimeout(suppressedClickState.timeoutId);
        }
        suppressedClickState = null;
    }

    function suppressNextFrameClick(frameEl) {
        clearSuppressedClickState();
        suppressedClickState = {
            frameEl,
            timeoutId: window.setTimeout(clearSuppressedClickState, clickSuppressionMs),
        };
    }

    document.addEventListener('pointerdown', function (event) {
        if (!(event.target instanceof Element)) return;
        if (event.pointerType !== 'mouse') return;
        if (event.button !== 0) return;

        const frameEl = findTimesheetFrame(event.target);
        if (!(frameEl instanceof HTMLElement)) return;
        if (frameEl.scrollWidth <= frameEl.clientWidth) return;

        dragState = {
            frameEl,
            pointerId: event.pointerId,
            startX: event.clientX,
            startScrollLeft: frameEl.scrollLeft,
            dragging: false,
        };
    });

    document.addEventListener('pointermove', function (event) {
        if (!dragState || dragState.pointerId !== event.pointerId) return;

        const deltaX = event.clientX - dragState.startX;
        if (!dragState.dragging && Math.abs(deltaX) < dragThreshold) return;

        if (!dragState.dragging) {
            dragState.dragging = true;
            dragState.frameEl.dataset.timesheetDayColumnsDragging = 'true';

            const selection = window.getSelection && window.getSelection();
            if (selection) selection.removeAllRanges();

            try {
                dragState.frameEl.setPointerCapture(event.pointerId);
            } catch (_error) {
                // best effort only
            }
        }

        dragState.frameEl.scrollLeft = dragState.startScrollLeft - deltaX;
        event.preventDefault();
    }, { passive: false });

    function endTimesheetDayColumnDrag(event) {
        if (!dragState || dragState.pointerId !== event.pointerId) return;

        const frameEl = dragState.frameEl;
        const hadDrag = dragState.dragging;

        frameEl.removeAttribute('data-timesheet-day-columns-dragging');
        if (frameEl.hasPointerCapture(dragState.pointerId)) {
            frameEl.releasePointerCapture(dragState.pointerId);
        }
        dragState = null;

        if (hadDrag) {
            suppressNextFrameClick(frameEl);
        }
    }

    document.addEventListener('pointerup', endTimesheetDayColumnDrag);
    document.addEventListener('pointercancel', endTimesheetDayColumnDrag);

    document.addEventListener('click', function (event) {
        if (!suppressedClickState) return;

        const frameEl = findTimesheetFrame(event.target);
        if (frameEl !== suppressedClickState.frameEl) {
            clearSuppressedClickState();
            return;
        }

        event.preventDefault();
        event.stopPropagation();
        clearSuppressedClickState();
    }, true);
})();

(function blurPointerOpenedTimesheetEntryAfterDialogClose() {
    if (typeof window === 'undefined') return;

    const dialogMountId = 'dialog-overlay-mount';
    const entryLinkSelector = '.timesheet-entry-card-link';
    let pointerOpenedEntryLink = null;
    let mountObserver = null;

    function getDialogMount() {
        return document.getElementById(dialogMountId);
    }

    function clearTrackedEntryLink() {
        pointerOpenedEntryLink = null;
    }

    function blurTrackedEntryLinkIfFocused() {
        const linkEl = pointerOpenedEntryLink;
        clearTrackedEntryLink();

        if (!(linkEl instanceof HTMLElement)) return;
        if (!document.contains(linkEl)) return;
        if (document.activeElement === linkEl) {
            linkEl.blur();
        }
    }

    function isDialogMountEmpty() {
        const mountEl = getDialogMount();
        return mountEl instanceof HTMLElement && mountEl.children.length === 0;
    }

    function handlePossibleDialogClose() {
        if (!pointerOpenedEntryLink) return;
        if (!isDialogMountEmpty()) return;

        window.requestAnimationFrame(blurTrackedEntryLinkIfFocused);
    }

    document.addEventListener('pointerdown', function (event) {
        if (!(event.target instanceof Element)) return;

        const linkEl = event.target.closest(entryLinkSelector);
        if (linkEl instanceof HTMLElement) {
            pointerOpenedEntryLink = linkEl;
        }
    }, true);

    document.addEventListener('keydown', clearTrackedEntryLink, true);

    function ensureMountObserver() {
        if (mountObserver) return;
        if (!window.MutationObserver) return;

        const mountEl = getDialogMount();
        if (!(mountEl instanceof HTMLElement)) return;

        mountObserver = new MutationObserver(handlePossibleDialogClose);
        mountObserver.observe(mountEl, { childList: true });
    }

    document.addEventListener('DOMContentLoaded', ensureMountObserver);
    document.addEventListener('app:page-ready', function () {
        ensureMountObserver();
        handlePossibleDialogClose();
    });
})();
