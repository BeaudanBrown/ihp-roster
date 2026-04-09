// Shared workflow dialog mount for HTMX-driven form overlays.
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

(function preserveRosterFilterDropdownState() {
    if (typeof window === 'undefined') return;

    let pendingMenuTriggerId = null;

    document.addEventListener('htmx:beforeRequest', function (event) {
        const sourceEl = event.detail && event.detail.elt;
        if (!(sourceEl instanceof HTMLElement)) return;

        const formEl = sourceEl.closest('[data-roster-filter-form="true"]');
        if (!(formEl instanceof HTMLElement)) return;

        pendingMenuTriggerId = formEl.dataset.rosterFilterMenuTriggerId || null;
    });

    document.addEventListener('htmx:afterSwap', function (event) {
        if (!pendingMenuTriggerId) return;
        if (!(event.detail && event.detail.target instanceof HTMLElement)) return;
        if (event.detail.target.id !== 'roster-content') return;
        if (!(window.bootstrap && window.bootstrap.Dropdown)) return;

        const triggerEl = document.getElementById(pendingMenuTriggerId);
        pendingMenuTriggerId = null;
        if (!(triggerEl instanceof HTMLElement)) return;

        window.requestAnimationFrame(function () {
            const dropdown = window.bootstrap.Dropdown.getOrCreateInstance(triggerEl);
            dropdown.show();
        });
    });

    document.addEventListener('htmx:responseError', function () {
        pendingMenuTriggerId = null;
    });
})();

// Bottom-right toast host for redirects and HTMX-triggered transient messages.
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

    document.addEventListener('app:page-ready', initHostToasts);
})();

// Defer auto-refresh updates for rows that are actively being edited.
// This prevents in-progress edits from being clobbered by live updates while still replaying the latest row after blur.
(function enableRosterGridAutoRefreshDeferral() {
    if (typeof window === 'undefined' || typeof window.morphdom !== 'function') return;

    const pendingRows = new Map();
    const baseMorphdom = window.morphdom;

    function hasActiveDeferredRosterInput(rowEl) {
        return Boolean(rowEl.querySelector('.slot-note-input:focus'));
    }

    function findPreservedField(root, preserveField) {
        if (!(root instanceof HTMLElement) || !preserveField) return null;

        const fieldKey = preserveField.fieldKey;
        if (fieldKey) {
            const escapedKey = window.CSS && typeof window.CSS.escape === 'function'
                ? window.CSS.escape(fieldKey)
                : fieldKey;
            const keyedField = root.querySelector(`[data-roster-field-key="${escapedKey}"]`);
            if (keyedField instanceof HTMLInputElement || keyedField instanceof HTMLSelectElement || keyedField instanceof HTMLTextAreaElement) {
                return keyedField;
            }
        }

        const name = preserveField.name;
        if (!name) return null;
        const escapedName = window.CSS && typeof window.CSS.escape === 'function'
            ? window.CSS.escape(name)
            : name;
        const namedField = root.querySelector(`[name="${escapedName}"]`);
        if (namedField instanceof HTMLInputElement || namedField instanceof HTMLSelectElement || namedField instanceof HTMLTextAreaElement) {
            return namedField;
        }

        return null;
    }

    function applyPendingRow(rowId, preserveField) {
        const pendingMarkup = pendingRows.get(rowId);
        if (!pendingMarkup) return;

        const currentRow = document.getElementById(rowId);
        if (!currentRow) {
            pendingRows.delete(rowId);
            return;
        }

        const template = document.createElement('template');
        template.innerHTML = pendingMarkup.trim();
        const nextRow = template.content.firstElementChild;
        if (!nextRow) {
            pendingRows.delete(rowId);
            return;
        }

        pendingRows.delete(rowId);
        baseMorphdom(currentRow, nextRow);

        const field = findPreservedField(currentRow, preserveField);
        if (field) {
            field.value = preserveField.value;
        }
    }

    window.morphdom = function (fromNode, toNode, options) {
        const baseOnBeforeElUpdated = options && typeof options.onBeforeElUpdated === 'function'
            ? options.onBeforeElUpdated
            : null;
        const baseOnBeforeElChildrenUpdated = options && typeof options.onBeforeElChildrenUpdated === 'function'
            ? options.onBeforeElChildrenUpdated
            : null;

        if (options) {
            options = {
                ...options,
                onBeforeElChildrenUpdated: function (fromEl, toEl) {
                    const isRosterControl =
                        fromEl instanceof HTMLElement &&
                        fromEl.closest('.roster-grid') &&
                        (fromEl.tagName === 'INPUT'
                            || fromEl.tagName === 'SELECT'
                            || fromEl.tagName === 'TEXTAREA'
                            || fromEl.tagName === 'OPTION');

                    // Skip IHP's value-preservation hook for roster controls so server truth is reflected.
                    if (isRosterControl) {
                        return;
                    }

                    if (baseOnBeforeElChildrenUpdated) {
                        return baseOnBeforeElChildrenUpdated(fromEl, toEl);
                    }

                    return true;
                },
                onBeforeElUpdated: function (fromEl, toEl) {
                    if (baseOnBeforeElUpdated && baseOnBeforeElUpdated(fromEl, toEl) === false) {
                        return false;
                    }

                    const isRosterRow =
                        fromEl instanceof HTMLElement &&
                        toEl instanceof HTMLElement &&
                        fromEl.matches('tr[data-roster-row]') &&
                        toEl.matches('tr[data-roster-row]');

                    if (isRosterRow && hasActiveDeferredRosterInput(fromEl)) {
                        const rowId = fromEl.id;
                        if (rowId) {
                            pendingRows.set(rowId, toEl.outerHTML);
                        }
                        return false;
                    }

                    return true;
                },
            };
        }

        return baseMorphdom(fromNode, toNode, options);
    };

    document.addEventListener('focusout', function (event) {
        const target = event.target;
        if (!(target instanceof HTMLElement)) return;
        if (!target.classList.contains('slot-note-input')) return;

        const rowEl = target.closest('tr[data-roster-row]');
        if (!rowEl || !rowEl.id) return;
        const preserveField = {
            fieldKey: target.dataset.rosterFieldKey || null,
            name: target.getAttribute('name'),
            value: target.value,
        };

        // Wait until focus has potentially moved to another input in the same row.
        window.setTimeout(function () {
            if (!hasActiveDeferredRosterInput(rowEl)) {
                applyPendingRow(rowEl.id, preserveField);
            }
        }, 0);
    });
})();

// Reusable quarter-hour modal time picker.
// Any field using [data-time-picker-field] + .js-time-picker-input + .js-time-picker-trigger
// can opt into this behavior.
(function enableQuarterHourTimePicker() {
    if (typeof window === 'undefined') return;

    const modalId = 'quarter-hour-time-picker-modal';
    const defaultEmptyLabel = 'Time';
    let activeField = null;

    function getModalElement() {
        return document.getElementById(modalId);
    }

    function getBootstrapModal(modalEl) {
        if (!modalEl || !window.bootstrap || !window.bootstrap.Modal) return null;
        return window.bootstrap.Modal.getOrCreateInstance(modalEl);
    }

    function forceHideModal(modalEl) {
        if (!modalEl) return;

        modalEl.classList.remove('show');
        modalEl.style.display = 'none';
        modalEl.setAttribute('aria-hidden', 'true');
        modalEl.removeAttribute('aria-modal');
        document.body.classList.remove('modal-open');
        document.body.style.removeProperty('padding-right');
        document.querySelectorAll('.modal-backdrop').forEach(function (backdropEl) {
            backdropEl.remove();
        });
        activeField = null;
    }

    function hideTimePickerModal(modalEl) {
        if (!modalEl) return;

        const bootstrapModal = getBootstrapModal(modalEl);
        if (bootstrapModal) bootstrapModal.hide();

        window.setTimeout(function () {
            if (modalEl.classList.contains('show')) {
                forceHideModal(modalEl);
            }
        }, 150);
    }

    function getFieldInput(fieldEl) {
        return fieldEl ? fieldEl.querySelector('.js-time-picker-input') : null;
    }

    function getFieldLabel(fieldEl) {
        return fieldEl ? fieldEl.querySelector('.js-time-picker-label') : null;
    }

    function getStepDownButton(fieldEl) {
        return fieldEl ? fieldEl.querySelector('.js-time-picker-step-down') : null;
    }

    function getStepUpButton(fieldEl) {
        return fieldEl ? fieldEl.querySelector('.js-time-picker-step-up') : null;
    }

    function emptyLabelForField(fieldEl) {
        if (!(fieldEl instanceof HTMLElement)) return defaultEmptyLabel;
        return fieldEl.dataset.timePickerEmptyLabel || defaultEmptyLabel;
    }

    function findOptionByValue(modalEl, value) {
        if (!modalEl) return null;
        return modalEl.querySelector(`.js-time-picker-option[data-time-value="${value}"]`);
    }

    function minuteOfDayFromValue(value) {
        if (!value || !/^\d{2}:\d{2}$/.test(value)) return null;
        const parts = value.split(':');
        const hour = Number(parts[0]);
        const minute = Number(parts[1]);
        if (!Number.isInteger(hour) || !Number.isInteger(minute)) return null;
        if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
        return hour * 60 + minute;
    }

    function displayLabelFromValue(value) {
        const minuteOfDay = minuteOfDayFromValue(value);
        if (minuteOfDay === null) return value;

        const hour24 = Math.floor(minuteOfDay / 60);
        const minute = minuteOfDay % 60;
        const meridiem = hour24 >= 12 ? 'PM' : 'AM';
        const hour12 = hour24 % 12 === 0 ? 12 : hour24 % 12;
        const minuteLabel = String(minute).padStart(2, '0');
        return `${hour12}:${minuteLabel} ${meridiem}`;
    }

    function resolveRange(fieldEl, modalEl) {
        const defaultStart = (modalEl && modalEl.dataset.defaultStartTime) || '06:00';
        const defaultEnd = (modalEl && modalEl.dataset.defaultEndTime) || '23:45';
        const startValue = (fieldEl && fieldEl.dataset.timePickerStart) || defaultStart;
        const endValue = (fieldEl && fieldEl.dataset.timePickerEnd) || defaultEnd;

        const startMinute = minuteOfDayFromValue(startValue);
        const endMinuteRaw = minuteOfDayFromValue(endValue);
        if (startMinute === null || endMinuteRaw === null) return null;

        const endMinute = endMinuteRaw < startMinute ? endMinuteRaw + 24 * 60 : endMinuteRaw;
        return { startMinute, endMinute };
    }

    function stepMinutesForField(fieldEl) {
        const rawValue = fieldEl && fieldEl.dataset.timePickerStepMinutes;
        const parsed = Number(rawValue || '15');
        if (!Number.isInteger(parsed) || parsed <= 0) return 15;
        return parsed;
    }

    function buildTimeOptions(range) {
        return buildTimeOptionsWithStep(range, 15);
    }

    function buildTimeOptionsWithStep(range, stepMinutes) {
        if (!range) return [];

        const options = [];
        for (let minute = range.startMinute; minute <= range.endMinute; minute += stepMinutes) {
            const minuteOfDay = minute % (24 * 60);
            const hour = Math.floor(minuteOfDay / 60);
            const minutePart = minuteOfDay % 60;
            const value = `${String(hour).padStart(2, '0')}:${String(minutePart).padStart(2, '0')}`;
            options.push({ value, label: displayLabelFromValue(value) });
        }
        return options;
    }

    function buildFieldOptions(fieldEl, modalEl) {
        const range = resolveRange(fieldEl, modalEl);
        if (!range) return [];
        return buildTimeOptionsWithStep(range, stepMinutesForField(fieldEl));
    }

    function renderOptions(modalEl, fieldEl) {
        if (!modalEl) return;
        const gridEl = modalEl.querySelector('.js-time-picker-grid');
        if (!gridEl) return;

        const options = buildFieldOptions(fieldEl, modalEl);
        gridEl.innerHTML = options
            .map(function (option) {
                return (
                    `<button type="button" class="btn btn-outline-secondary time-picker-option js-time-picker-option" data-time-value="${option.value}">` +
                    `${option.label}</button>`
                );
            })
            .join('');
    }

    function updateFieldLabel(fieldEl, value, explicitLabel) {
        const labelEl = getFieldLabel(fieldEl);
        if (!labelEl) return;

        if (!value) {
            labelEl.textContent = emptyLabelForField(fieldEl);
            labelEl.classList.add('app-muted');
            return;
        }

        labelEl.textContent = explicitLabel || value;
        labelEl.classList.remove('app-muted');
    }

    function highlightSelectedOption(modalEl, value) {
        if (!modalEl) return;

        modalEl.querySelectorAll('.js-time-picker-option').forEach(function (optionEl) {
            const isSelected = value && optionEl.dataset.timeValue === value;
            optionEl.classList.toggle('active', Boolean(isSelected));
            optionEl.classList.toggle('btn-primary', Boolean(isSelected));
            optionEl.classList.toggle('btn-outline-secondary', !isSelected);
        });
    }

    function applyTimeValue(fieldEl, value, labelText) {
        const inputEl = getFieldInput(fieldEl);
        if (!inputEl || inputEl.disabled) return;

        const previousValue = inputEl.value || '';
        const nextValue = value || '';

        updateFieldLabel(fieldEl, nextValue, labelText);
        if (previousValue === nextValue) return;

        inputEl.value = nextValue;
        inputEl.dispatchEvent(new Event('input', { bubbles: true }));
        if (window.htmx && typeof window.htmx.trigger === 'function') {
            window.htmx.trigger(inputEl, 'change');
        } else {
            inputEl.dispatchEvent(new Event('change', { bubbles: true }));
        }
    }

    function syncFieldControls(fieldEl) {
        if (!(fieldEl instanceof HTMLElement)) return;

        const inputEl = getFieldInput(fieldEl);
        if (!inputEl) return;

        const triggerEl = fieldEl.querySelector('.js-time-picker-trigger');
        const stepDownEl = getStepDownButton(fieldEl);
        const stepUpEl = getStepUpButton(fieldEl);
        const isFieldDisabled = Boolean(inputEl.disabled);
        const options = buildFieldOptions(fieldEl, getModalElement());
        const currentValue = inputEl.value || '';
        const selectedIndex = options.findIndex(function (option) {
            return option.value === currentValue;
        });
        const hasSelection = selectedIndex >= 0;

        if (triggerEl) triggerEl.disabled = isFieldDisabled;
        if (stepDownEl) stepDownEl.disabled = isFieldDisabled || !hasSelection || selectedIndex === 0;
        if (stepUpEl) stepUpEl.disabled = isFieldDisabled || !hasSelection || selectedIndex === options.length - 1;
    }

    function stepFieldValue(fieldEl, direction) {
        if (!(fieldEl instanceof HTMLElement)) return;

        const inputEl = getFieldInput(fieldEl);
        if (!inputEl || inputEl.disabled) return;

        const options = buildFieldOptions(fieldEl, getModalElement());
        const currentValue = inputEl.value || '';
        const selectedIndex = options.findIndex(function (option) {
            return option.value === currentValue;
        });
        if (selectedIndex < 0) {
            syncFieldControls(fieldEl);
            return;
        }

        const nextIndex = selectedIndex + direction;
        if (nextIndex < 0 || nextIndex >= options.length) {
            syncFieldControls(fieldEl);
            return;
        }

        const nextOption = options[nextIndex];
        applyTimeValue(fieldEl, nextOption.value, nextOption.label);
        syncFieldControls(fieldEl);
    }

    document.addEventListener('click', function (event) {
        const triggerEl = event.target.closest('.js-time-picker-trigger');
        if (!triggerEl) return;
        if (triggerEl.disabled) return;

        const fieldEl = triggerEl.closest('[data-time-picker-field]');
        const inputEl = getFieldInput(fieldEl);
        if (!fieldEl || !inputEl || inputEl.disabled) return;

        const modalEl = getModalElement();
        const bootstrapModal = getBootstrapModal(modalEl);
        if (!modalEl || !bootstrapModal) return;

        activeField = fieldEl;
        renderOptions(modalEl, fieldEl);
        highlightSelectedOption(modalEl, inputEl.value || '');
        bootstrapModal.show();
    });

    document.addEventListener('click', function (event) {
        const stepDownEl = event.target.closest('.js-time-picker-step-down');
        if (!stepDownEl) return;
        if (stepDownEl.disabled) return;

        const fieldEl = stepDownEl.closest('[data-time-picker-field]');
        stepFieldValue(fieldEl, -1);
    });

    document.addEventListener('click', function (event) {
        const stepUpEl = event.target.closest('.js-time-picker-step-up');
        if (!stepUpEl) return;
        if (stepUpEl.disabled) return;

        const fieldEl = stepUpEl.closest('[data-time-picker-field]');
        stepFieldValue(fieldEl, 1);
    });

    document.addEventListener('click', function (event) {
        const optionEl = event.target.closest('.js-time-picker-option');
        if (!optionEl) return;
        if (!activeField) return;

        const modalEl = getModalElement();
        const value = optionEl.dataset.timeValue || '';
        const labelText = optionEl.textContent ? optionEl.textContent.trim() : value;

        applyTimeValue(activeField, value, labelText);
        highlightSelectedOption(modalEl, value);
        syncFieldControls(activeField);
        hideTimePickerModal(modalEl);
    });

    document.addEventListener('click', function (event) {
        const clearButton = event.target.closest('.js-time-picker-clear');
        if (!clearButton) return;
        if (!activeField) return;

        const modalEl = getModalElement();

        applyTimeValue(activeField, '', emptyLabelForField(activeField));
        highlightSelectedOption(modalEl, '');
        syncFieldControls(activeField);
        hideTimePickerModal(modalEl);
    });

    document.addEventListener('hidden.bs.modal', function (event) {
        const modalEl = event.target;
        if (!(modalEl instanceof HTMLElement)) return;
        if (modalEl.id !== modalId) return;

        activeField = null;
    });

    function syncFieldLabelsWithin(root) {
        if (!(root instanceof Element || root instanceof Document)) return;

        const fieldsToSync = new Set();

        if (root instanceof Element) {
            if (root.matches('[data-time-picker-field]')) {
                fieldsToSync.add(root);
            }

            const closestField = root.closest('[data-time-picker-field]');
            if (closestField instanceof HTMLElement) {
                fieldsToSync.add(closestField);
            }
        }

        root.querySelectorAll('[data-time-picker-field]').forEach(function (fieldEl) {
            fieldsToSync.add(fieldEl);
        });

        fieldsToSync.forEach(function (fieldEl) {
            const inputEl = getFieldInput(fieldEl);
            if (!inputEl) return;
            const modalEl = getModalElement();
            const selectedOption = findOptionByValue(modalEl, inputEl.value || '');
            const selectedLabel = selectedOption ? selectedOption.textContent.trim() : displayLabelFromValue(inputEl.value);
            updateFieldLabel(fieldEl, inputEl.value || '', selectedLabel);
            syncFieldControls(fieldEl);
        });
    }

    document.addEventListener('app:page-ready', function (event) {
        syncFieldLabelsWithin((event.detail && event.detail.target) || document);
    });

    document.addEventListener('time-picker:sync', function (event) {
        syncFieldLabelsWithin((event.detail && event.detail.target) || document);
    });

})();

// Client-side sorting for the compact roster staff table.
(function enableRosterStaffPanelSorting() {
    if (typeof window === 'undefined') return;

    function compareText(leftValue, rightValue) {
        return leftValue.localeCompare(rightValue, undefined, { sensitivity: 'base' });
    }

    function compareNumber(leftValue, rightValue) {
        return leftValue - rightValue;
    }

    function parseNumber(value) {
        const parsed = Number.parseInt(value || '0', 10);
        return Number.isFinite(parsed) ? parsed : 0;
    }

    function compareRows(leftRow, rightRow, key, direction) {
        const directionMultiplier = direction === 'descending' ? -1 : 1;

        if (key === 'shifts') {
            const assignedResult =
                compareNumber(
                    parseNumber(leftRow.dataset.rosterStaffAssigned),
                    parseNumber(rightRow.dataset.rosterStaffAssigned),
                ) * directionMultiplier;
            if (assignedResult !== 0) return assignedResult;

            const idealResult =
                compareNumber(
                    parseNumber(leftRow.dataset.rosterStaffIdeal),
                    parseNumber(rightRow.dataset.rosterStaffIdeal),
                ) * directionMultiplier;
            if (idealResult !== 0) return idealResult;

            return compareText(
                leftRow.dataset.rosterStaffName || '',
                rightRow.dataset.rosterStaffName || '',
            );
        }

        if (key === 'role') {
            const roleResult =
                compareText(
                    leftRow.dataset.rosterStaffRole || '',
                    rightRow.dataset.rosterStaffRole || '',
                ) * directionMultiplier;
            if (roleResult !== 0) return roleResult;

            return compareText(
                leftRow.dataset.rosterStaffName || '',
                rightRow.dataset.rosterStaffName || '',
            );
        }

        return compareText(
            leftRow.dataset.rosterStaffName || '',
            rightRow.dataset.rosterStaffName || '',
        ) * directionMultiplier;
    }

    function syncSortButtonStates(tableEl, activeKey, direction) {
        tableEl.querySelectorAll('[data-roster-staff-sort-key]').forEach(function (buttonEl) {
            if (!(buttonEl instanceof HTMLButtonElement)) return;

            const isActive = buttonEl.dataset.rosterStaffSortKey === activeKey;
            buttonEl.setAttribute('aria-sort', isActive ? direction : 'none');

            const headerCell = buttonEl.closest('th');
            if (headerCell instanceof HTMLTableCellElement) {
                headerCell.setAttribute('aria-sort', isActive ? direction : 'none');
            }
        });
    }

    function sortRosterStaffTable(tableEl, key, direction) {
        const tbodyEl = tableEl.querySelector('.roster-staff-table-body');
        if (!(tbodyEl instanceof HTMLTableSectionElement)) return;

        const rows = Array.from(tbodyEl.querySelectorAll('.roster-staff-panel-entry'));
        rows.sort(function (leftRow, rightRow) {
            return compareRows(leftRow, rightRow, key, direction);
        });
        rows.forEach(function (rowEl) {
            tbodyEl.appendChild(rowEl);
        });

        tableEl.dataset.rosterStaffSortKey = key;
        tableEl.dataset.rosterStaffSortDirection = direction;
        syncSortButtonStates(tableEl, key, direction);
    }

    function nextDirection(tableEl, key) {
        const currentKey = tableEl.dataset.rosterStaffSortKey || '';
        const currentDirection = tableEl.dataset.rosterStaffSortDirection || 'none';

        if (currentKey === key && currentDirection === 'ascending') {
            return 'descending';
        }

        return 'ascending';
    }

    function initRosterStaffPanelSortingWithin(root) {
        if (!(root instanceof Element || root instanceof Document)) return;

        root.querySelectorAll('.roster-staff-table').forEach(function (tableEl) {
            if (!(tableEl instanceof HTMLTableElement)) return;

            const defaultKey = tableEl.dataset.rosterStaffSortKey || 'name';
            const defaultDirection = tableEl.dataset.rosterStaffSortDirection || 'ascending';
            sortRosterStaffTable(tableEl, defaultKey, defaultDirection);
        });
    }

    document.addEventListener('click', function (event) {
        const buttonEl = event.target.closest('[data-roster-staff-sort-key]');
        if (!(buttonEl instanceof HTMLButtonElement)) return;

        const tableEl = buttonEl.closest('.roster-staff-table');
        if (!(tableEl instanceof HTMLTableElement)) return;

        const key = buttonEl.dataset.rosterStaffSortKey || 'name';
        const direction = nextDirection(tableEl, key);
        sortRosterStaffTable(tableEl, key, direction);
    });

    document.addEventListener('app:page-ready', function (event) {
        initRosterStaffPanelSortingWithin((event.detail && event.detail.target) || document);
    });
})();

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
