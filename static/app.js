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

(function enableRosterWeekOverview() {
    if (typeof window === 'undefined') return;

    function updateOverviewSelection(panelEl, dayButton) {
        if (!(panelEl instanceof HTMLElement) || !(dayButton instanceof HTMLElement)) return;

        panelEl.querySelectorAll('[data-week-overview-day="true"]').forEach((button) => {
            if (button instanceof HTMLElement) {
                button.classList.toggle('is-selected', button === dayButton);
                button.setAttribute('aria-pressed', button === dayButton ? 'true' : 'false');
            }
        });

        const selectedLabel = panelEl.querySelector('[data-week-overview-selected-label="true"]');
        const leaveValue = panelEl.querySelector('[data-week-overview-leave-value="true"]');
        const assignedValue = panelEl.querySelector('[data-week-overview-assigned-value="true"]');
        const hoursValue = panelEl.querySelector('[data-week-overview-hours-value="true"]');
        const summaryText = panelEl.querySelector('[data-week-overview-summary-text="true"]');
        const weekLabel = panelEl.querySelector('[data-week-overview-week-label="true"]');
        const goLink = panelEl.querySelector('[data-week-overview-go-link="true"]');
        const detailsPanel = panelEl.querySelector('[data-week-overview-details-panel="true"]');

        const hasDetails = dayButton.dataset.weekOverviewDetails === 'true';
        const isClosed = dayButton.dataset.weekOverviewClosed === 'true';

        if (selectedLabel) selectedLabel.textContent = dayButton.dataset.weekOverviewLabel || '';
        if (leaveValue) leaveValue.textContent = hasDetails ? (dayButton.dataset.weekOverviewLeave || '0') : '—';
        if (assignedValue) assignedValue.textContent = hasDetails ? (dayButton.dataset.weekOverviewAssigned || '0') : '—';
        if (hoursValue) hoursValue.textContent = hasDetails ? (dayButton.dataset.weekOverviewHours || '0h') : '—';
        if (summaryText) summaryText.textContent = dayButton.dataset.weekOverviewSummary || '';
        if (weekLabel) weekLabel.textContent = `In ${dayButton.dataset.weekOverviewWeekLabel || ''}`;
        if (goLink instanceof HTMLAnchorElement && dayButton.dataset.weekOverviewUrl) {
            goLink.href = dayButton.dataset.weekOverviewUrl;
        }

        if (detailsPanel instanceof HTMLElement) {
            detailsPanel.classList.toggle('is-unloaded', !hasDetails);
            detailsPanel.classList.toggle('is-closed', isClosed);
        }
    }

    function selectToday(panelEl) {
        if (!(panelEl instanceof HTMLElement)) return;
        const today = panelEl.dataset.weekOverviewCurrentDate;
        if (!today) return;
        const button = panelEl.querySelector(`[data-week-overview-day="true"][data-week-overview-date="${today}"]`);
        if (button instanceof HTMLElement) {
            updateOverviewSelection(panelEl, button);
        }
    }

    document.addEventListener('click', function (event) {
        const dayButton = event.target.closest('[data-week-overview-day="true"]');
        if (dayButton instanceof HTMLElement) {
            const panelEl = dayButton.closest('[data-week-overview-panel="true"]');
            updateOverviewSelection(panelEl, dayButton);
            return;
        }

        const todayButton = event.target.closest('[data-week-overview-today="true"]');
        if (todayButton instanceof HTMLElement) {
            const panelEl = todayButton.closest('[data-week-overview-panel="true"]');
            selectToday(panelEl);
        }
    });

    document.addEventListener('shown.bs.dropdown', function (event) {
        const trigger = event.target;
        if (!(trigger instanceof HTMLElement)) return;
        const panelEl = trigger.parentElement?.querySelector('[data-week-overview-panel="true"]');
        if (!(panelEl instanceof HTMLElement)) return;

        const selectedButton = panelEl.querySelector('[data-week-overview-day="true"].is-selected');
        if (selectedButton instanceof HTMLElement) {
            updateOverviewSelection(panelEl, selectedButton);
        }
    });
})();

(function enableRosterImageExport() {
    if (typeof window === 'undefined') return;

    const exportConfigs = {
        png: { mimeType: 'image/png', extension: 'png' },
        jpg: { mimeType: 'image/jpeg', extension: 'jpg', quality: 0.92 },
    };
    const exportPixelRatio = 2;
    const exportMinWidth = 920;
    const exportMaxWidth = 1240;

    function waitForNextPaint() {
        return new Promise(function (resolve) {
            window.requestAnimationFrame(function () {
                window.requestAnimationFrame(resolve);
            });
        });
    }

    function sanitizeFilenamePart(value) {
        return (value || '')
            .trim()
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, '-')
            .replace(/^-+|-+$/g, '')
            .replace(/-{2,}/g, '-');
    }

    function formatTimeValue(value) {
        if (!value) return '';
        const match = /^(\d{2}):(\d{2})$/.exec(value.trim());
        if (!match) return value;

        const hours = Number.parseInt(match[1], 10);
        const minutes = match[2];
        if (!Number.isFinite(hours)) return value;

        const period = hours >= 12 ? 'PM' : 'AM';
        const displayHour = (hours % 12) || 12;
        return `${displayHour}:${minutes} ${period}`;
    }

    function textOrEmpty(value) {
        return (value || '').trim();
    }

    function replaceCellContents(cellEl, value) {
        if (!(cellEl instanceof HTMLElement)) return;

        const displayValue = textOrEmpty(value);
        cellEl.replaceChildren();
        cellEl.dataset.rosterExportText = displayValue;

        const valueEl = document.createElement('div');
        valueEl.className = 'slot-cell-export-value';
        if (!displayValue) {
            valueEl.classList.add('app-muted');
            valueEl.innerHTML = '&nbsp;';
        } else {
            valueEl.textContent = displayValue;
        }

        cellEl.appendChild(valueEl);
        cellEl.removeAttribute('title');
        cellEl.removeAttribute('data-conflict-message');
    }

    function normalizeDayLabelCell(cellEl) {
        if (!(cellEl instanceof HTMLElement)) return;

        cellEl.querySelectorAll('form, button, input, select, textarea').forEach(function (element) {
            element.remove();
        });
        cellEl.querySelectorAll('.roster-day-actions, .roster-day-actions-placeholder').forEach(function (element) {
            element.remove();
        });

        const lines = Array.from(cellEl.querySelectorAll('.roster-day-date, .roster-day-closed-label'))
            .map(function (element) {
                return textOrEmpty(element.textContent);
            })
            .filter(Boolean);
        cellEl.dataset.rosterExportText = lines.join('\n');
    }

    function normalizeExportTable(tableEl) {
        if (!(tableEl instanceof HTMLTableElement)) return tableEl;

        tableEl.classList.add('roster-export-table');

        const theadEl = tableEl.querySelector('thead');
        if (theadEl) {
            theadEl.remove();
        }

        tableEl.querySelectorAll('tr.day-row').forEach(function (rowEl) {
            if (!(rowEl instanceof HTMLTableRowElement)) return;

            Array.from(rowEl.cells).forEach(function (cellEl, cellIndex) {
                if (!(cellEl instanceof HTMLTableCellElement)) return;

                if (cellIndex === 0 && cellEl.classList.contains('day-label')) {
                    normalizeDayLabelCell(cellEl);
                    return;
                }

                if (cellEl.classList.contains('slot-empty-cell') || cellEl.classList.contains('slot-closed-cell')) {
                    replaceCellContents(cellEl, '');
                    return;
                }

                if (cellEl.classList.contains('slot-time-cell')) {
                    const pickerLabelEl = cellEl.querySelector('.js-time-picker-label');
                    const inputEl = cellEl.querySelector('.js-time-picker-input, .slot-time-input');
                    const timeValue =
                        textOrEmpty(pickerLabelEl && pickerLabelEl.textContent)
                        || formatTimeValue(inputEl instanceof HTMLInputElement ? inputEl.value : '');
                    replaceCellContents(cellEl, timeValue);
                    return;
                }

                if (cellEl.classList.contains('slot-staff-cell')) {
                    const staticValue = cellEl.querySelector('.slot-cell-static');
                    const selectEl = cellEl.querySelector('.slot-staff-input');
                    const selectedOption = selectEl instanceof HTMLSelectElement ? selectEl.selectedOptions[0] : null;
                    const staffValue =
                        textOrEmpty(staticValue && staticValue.textContent)
                        || textOrEmpty(selectedOption && selectedOption.textContent);
                    replaceCellContents(cellEl, staffValue);
                    return;
                }

                if (cellEl.classList.contains('slot-note-cell')) {
                    const staticValue = cellEl.querySelector('.slot-cell-static');
                    const inputEl = cellEl.querySelector('.slot-note-input');
                    const noteValue =
                        textOrEmpty(staticValue && staticValue.textContent)
                        || textOrEmpty(inputEl instanceof HTMLInputElement ? inputEl.value : '');
                    replaceCellContents(cellEl, noteValue);
                    return;
                }

                replaceCellContents(cellEl, cellEl.textContent || '');
            });
        });

        return tableEl;
    }

    function escapeXml(value) {
        return String(value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function parsePixelValue(value, fallbackValue) {
        const parsed = Number.parseFloat(value || '');
        return Number.isFinite(parsed) ? parsed : fallbackValue;
    }

    function isTransparentColor(colorValue) {
        if (!colorValue) return true;
        const normalizedValue = colorValue.trim().toLowerCase();
        return normalizedValue === 'transparent' || normalizedValue === 'rgba(0, 0, 0, 0)';
    }

    function buildCellTextSvg(cellEl, x, y, width, height) {
        if (!(cellEl instanceof HTMLElement)) return '';

        const lines = (cellEl.dataset.rosterExportText || cellEl.textContent || '')
            .split('\n')
            .map(function (line) {
                return line.trim();
            })
            .filter(Boolean);

        if (lines.length === 0) return '';

        const computedStyle = window.getComputedStyle(cellEl);
        const fontSize = parsePixelValue(computedStyle.fontSize, 12);
        const fontWeight = computedStyle.fontWeight || '400';
        const fontFamily = escapeXml(computedStyle.fontFamily || 'sans-serif');
        const textColor = computedStyle.color || '#ffffff';
        const textAlign = computedStyle.textAlign || 'center';
        const lineHeight = Math.max(fontSize * 1.15, 12);
        const blockHeight = lineHeight * lines.length;
        const startY = y + ((height - blockHeight) / 2) + (lineHeight * 0.78);

        let textAnchor = 'middle';
        let textX = x + (width / 2);
        if (textAlign === 'left' || textAlign === 'start') {
            textAnchor = 'start';
            textX = x + 8;
        } else if (textAlign === 'right' || textAlign === 'end') {
            textAnchor = 'end';
            textX = x + width - 8;
        }

        const tspans = lines.map(function (line, index) {
            return `<tspan x="${textX}" y="${startY + (index * lineHeight)}">${escapeXml(line)}</tspan>`;
        }).join('');

        return `<text font-family="${fontFamily}" font-size="${fontSize}" font-weight="${fontWeight}" fill="${escapeXml(textColor)}" text-anchor="${textAnchor}">${tspans}</text>`;
    }

    function buildTableSvgMarkup(surfaceEl, tableEl) {
        if (!(surfaceEl instanceof HTMLElement) || !(tableEl instanceof HTMLTableElement)) {
            throw new Error('Failed to measure roster export surface.');
        }

        const surfaceRect = surfaceEl.getBoundingClientRect();
        const tableRect = tableEl.getBoundingClientRect();
        const width = Math.ceil(surfaceRect.width);
        const height = Math.ceil(surfaceRect.height);
        const tableLeft = tableRect.left - surfaceRect.left;
        const tableTop = tableRect.top - surfaceRect.top;

        const parts = [
            `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">`,
            '<defs>',
            '<linearGradient id="rosterExportBg" x1="0%" y1="0%" x2="0%" y2="100%">',
            '<stop offset="0%" stop-color="#1a2331" />',
            '<stop offset="100%" stop-color="#0f1622" />',
            '</linearGradient>',
            '</defs>',
            `<rect x="0" y="0" width="${width}" height="${height}" fill="url(#rosterExportBg)" />`,
        ];

        tableEl.querySelectorAll('tbody tr').forEach(function (rowEl) {
            if (!(rowEl instanceof HTMLTableRowElement)) return;

            const rowRect = rowEl.getBoundingClientRect();
            const rowStyle = window.getComputedStyle(rowEl);
            const rowFill = rowStyle.backgroundColor;
            if (!isTransparentColor(rowFill)) {
                const rowY = rowRect.top - surfaceRect.top;
                parts.push(
                    `<rect x="${tableLeft}" y="${rowY}" width="${tableRect.width}" height="${rowRect.height}" fill="${escapeXml(rowFill)}" />`,
                );
            }
        });

        tableEl.querySelectorAll('tbody td').forEach(function (cellEl) {
            if (!(cellEl instanceof HTMLTableCellElement)) return;

            const cellRect = cellEl.getBoundingClientRect();
            const cellStyle = window.getComputedStyle(cellEl);
            const x = cellRect.left - surfaceRect.left;
            const y = cellRect.top - surfaceRect.top;
            const fill = isTransparentColor(cellStyle.backgroundColor) ? 'none' : escapeXml(cellStyle.backgroundColor);
            const stroke = escapeXml(cellStyle.borderTopColor || '#3a4658');
            const strokeWidth = Math.max(1, parsePixelValue(cellStyle.borderTopWidth, 1));

            parts.push(
                `<rect x="${x}" y="${y}" width="${cellRect.width}" height="${cellRect.height}" fill="${fill}" stroke="${stroke}" stroke-width="${strokeWidth}" shape-rendering="crispEdges" />`,
            );
            parts.push(buildCellTextSvg(cellEl, x, y, cellRect.width, cellRect.height));
        });

        parts.push('</svg>');
        return { width, height, svgMarkup: parts.join('') };
    }

    async function exportSurfaceToBlob(surfaceEl, tableEl, formatConfig) {
        const renderSpec = buildTableSvgMarkup(surfaceEl, tableEl);
        const svgBlob = new Blob([renderSpec.svgMarkup], { type: 'image/svg+xml;charset=utf-8' });
        const svgUrl = URL.createObjectURL(svgBlob);

        try {
            const imageEl = await new Promise(function (resolve, reject) {
                const image = new window.Image();
                image.decoding = 'async';
                image.onload = function () {
                    resolve(image);
                };
                image.onerror = function () {
                    reject(new Error('Failed to render roster export image.'));
                };
                image.src = svgUrl;
            });

            const canvasEl = document.createElement('canvas');
            canvasEl.width = renderSpec.width * exportPixelRatio;
            canvasEl.height = renderSpec.height * exportPixelRatio;

            const context = canvasEl.getContext('2d');
            if (!context) {
                throw new Error('Failed to initialize roster export canvas.');
            }

            context.scale(exportPixelRatio, exportPixelRatio);
            context.drawImage(imageEl, 0, 0, renderSpec.width, renderSpec.height);

            return await new Promise(function (resolve, reject) {
                canvasEl.toBlob(function (blob) {
                    if (blob) {
                        resolve(blob);
                        return;
                    }
                    reject(new Error('Failed to encode roster export image.'));
                }, formatConfig.mimeType, formatConfig.quality);
            });
        } finally {
            URL.revokeObjectURL(svgUrl);
        }
    }

    async function buildRosterExportBlob(formatConfig) {
        const rosterTable = document.querySelector('#roster-content .roster-grid');
        if (!(rosterTable instanceof HTMLTableElement)) {
            throw new Error('Could not find the current roster grid.');
        }

        const exportTable = normalizeExportTable(rosterTable.cloneNode(true));
        const stageEl = document.createElement('div');
        stageEl.className = 'roster-export-stage';

        const surfaceEl = document.createElement('div');
        surfaceEl.className = 'roster-export-surface';
        const measuredWidth = Math.ceil(rosterTable.getBoundingClientRect().width + 56);
        const exportWidth = Math.max(exportMinWidth, Math.min(exportMaxWidth, measuredWidth));
        surfaceEl.style.width = `${exportWidth}px`;
        surfaceEl.appendChild(exportTable);
        stageEl.appendChild(surfaceEl);
        document.body.appendChild(stageEl);

        try {
            if (document.fonts && typeof document.fonts.ready === 'object') {
                await document.fonts.ready;
            }
            await waitForNextPaint();
            return await exportSurfaceToBlob(surfaceEl, exportTable, formatConfig);
        } finally {
            stageEl.remove();
        }
    }

    function exportFilename(formatConfig) {
        const groupSelect = document.getElementById('roster-group-switch');
        const groupLabel = groupSelect instanceof HTMLSelectElement && groupSelect.selectedOptions[0]
            ? groupSelect.selectedOptions[0].textContent
            : 'group';
        const weekLabelEl = document.querySelector('.roster-week-overview-trigger span:last-child');
        const weekLabel = weekLabelEl ? weekLabelEl.textContent : 'week';

        const parts = ['roster', sanitizeFilenamePart(groupLabel || ''), sanitizeFilenamePart(weekLabel || '')]
            .filter(Boolean);
        return `${parts.join('-')}.${formatConfig.extension}`;
    }

    function triggerBlobDownload(blob, filename) {
        const downloadUrl = URL.createObjectURL(blob);
        const linkEl = document.createElement('a');
        linkEl.href = downloadUrl;
        linkEl.download = filename;
        document.body.appendChild(linkEl);
        linkEl.click();
        linkEl.remove();
        window.setTimeout(function () {
            URL.revokeObjectURL(downloadUrl);
        }, 1000);
    }

    async function handleRosterExport(buttonEl) {
        if (!(buttonEl instanceof HTMLButtonElement)) return;

        const formatKey = buttonEl.dataset.rosterExportFormat || 'png';
        const formatConfig = exportConfigs[formatKey];
        if (!formatConfig) return;

        const originalLabel = buttonEl.textContent;
        buttonEl.dataset.rosterExportStatus = 'working';
        document.body.dataset.rosterExportLastStatus = 'working';
        buttonEl.disabled = true;
        buttonEl.textContent = 'Preparing...';

        try {
            const blob = await buildRosterExportBlob(formatConfig);
            triggerBlobDownload(blob, exportFilename(formatConfig));
            buttonEl.dataset.rosterExportStatus = 'success';
            document.body.dataset.rosterExportLastStatus = 'success';
            buttonEl.textContent = 'Downloaded';
            window.setTimeout(function () {
                buttonEl.textContent = originalLabel;
            }, 1200);
        } catch (error) {
            console.error(error);
            buttonEl.dataset.rosterExportStatus = 'error';
            document.body.dataset.rosterExportLastStatus = 'error';
            buttonEl.textContent = 'Export failed';
            window.setTimeout(function () {
                buttonEl.textContent = originalLabel;
            }, 1600);
            window.alert('Roster export failed. Please try again.');
        } finally {
            window.setTimeout(function () {
                buttonEl.disabled = false;
            }, 200);
        }
    }

    document.addEventListener('click', function (event) {
        const buttonEl = event.target.closest('[data-roster-export-format]');
        if (!(buttonEl instanceof HTMLButtonElement)) return;

        event.preventDefault();
        handleRosterExport(buttonEl);
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
