// @ts-nocheck

import { enableRosterColumnEditMode } from "./roster/column-edit";
import { rosterFullscreenLabels } from "./roster/fullscreen";
import { rosterOverviewSummaryFromDayDataset } from "./roster/overview";
import { enableRosterStaffPanelSorting } from "./roster/staff-panel-sorting";
import { compareRosterStaffData, rosterParseNumber } from "./roster/staff-sort";

export { rosterFullscreenLabels, rosterOverviewSummaryFromDayDataset, compareRosterStaffData, rosterParseNumber };

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

        const summary = rosterOverviewSummaryFromDayDataset(dayButton.dataset);

        if (selectedLabel) selectedLabel.textContent = summary.label;
        if (leaveValue) leaveValue.textContent = summary.leave;
        if (assignedValue) assignedValue.textContent = summary.assigned;
        if (hoursValue) hoursValue.textContent = summary.hours;
        if (summaryText) summaryText.textContent = summary.summary;
        if (weekLabel) weekLabel.textContent = summary.weekLabel;
        if (goLink instanceof HTMLAnchorElement && summary.url) {
            goLink.href = summary.url;
        }

        if (detailsPanel instanceof HTMLElement) {
            detailsPanel.classList.toggle('is-unloaded', !summary.hasDetails);
            detailsPanel.classList.toggle('is-closed', summary.isClosed);
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

(function enableRosterFullscreenToggle() {
    if (typeof window === 'undefined') return;

    const shellSelector = '#roster-week-shell';
    const toggleSelector = '[data-roster-fullscreen-toggle="true"]';
    const labelSelector = '[data-roster-fullscreen-toggle-label="true"]';
    const expandedLabel = 'Exit expanded roster';
    const collapsedLabel = 'Expand roster';

    function rosterShellFromToggle(toggle) {
        return toggle.closest(shellSelector);
    }

    function isExpanded(shell) {
        return shell instanceof HTMLElement && shell.dataset.rosterFullscreen === 'true';
    }

    function updateToggle(toggle, expanded) {
        const labels = rosterFullscreenLabels(expanded);
        toggle.setAttribute('aria-pressed', labels.pressed);
        toggle.setAttribute('aria-label', labels.label);
        toggle.setAttribute('title', labels.label);

        const label = toggle.querySelector(labelSelector);
        if (label) label.textContent = labels.label;

        const icon = toggle.querySelector('.bi');
        if (icon) {
            icon.classList.toggle(labels.iconRemove, false);
            icon.classList.toggle(labels.iconAdd, true);
        }
    }

    function syncShell(shell) {
        if (!(shell instanceof HTMLElement)) return;
        const expanded = isExpanded(shell);
        shell.querySelectorAll(toggleSelector).forEach(function (toggle) {
            if (toggle instanceof HTMLElement) updateToggle(toggle, expanded);
        });
    }

    function syncAllShells() {
        document.querySelectorAll(shellSelector).forEach(syncShell);
    }

    function setRosterFullscreen(shell, expanded, toggle) {
        if (!(shell instanceof HTMLElement)) return;
        shell.dataset.rosterFullscreen = expanded ? 'true' : 'false';
        syncShell(shell);

        if (expanded && toggle instanceof HTMLElement) {
            toggle.focus({ preventScroll: true });
        }
    }

    document.addEventListener('click', function (event) {
        if (!(event.target instanceof Element)) return;

        const toggle = event.target.closest(toggleSelector);
        if (!(toggle instanceof HTMLElement)) return;

        const shell = rosterShellFromToggle(toggle);
        if (!(shell instanceof HTMLElement)) return;

        setRosterFullscreen(shell, !isExpanded(shell), toggle);
    });

    document.addEventListener('keydown', function (event) {
        if (event.key !== 'Escape') return;

        const shell = document.querySelector(`${shellSelector}[data-roster-fullscreen="true"]`);
        if (shell instanceof HTMLElement) {
            setRosterFullscreen(shell, false, shell.querySelector(toggleSelector));
        }
    });

    document.addEventListener('htmx:afterSwap', syncAllShells);
    document.addEventListener('DOMContentLoaded', syncAllShells);
})();

enableRosterColumnEditMode();

(function enableRosterImageExport() {
    if (typeof window === 'undefined') return;

    const exportConfigs = {
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
        if (!(tableEl instanceof HTMLElement)) return tableEl;

        tableEl.classList.add('roster-export-grid');

        const theadEl = tableEl.querySelector('thead');
        if (theadEl) {
            theadEl.remove();
        }

        tableEl.querySelectorAll('.day-row').forEach(function (rowEl) {
            if (!(rowEl instanceof HTMLElement)) return;

            Array.from(rowEl.querySelectorAll('[role="gridcell"], td')).forEach(function (cellEl, cellIndex) {
                if (!(cellEl instanceof HTMLElement)) return;

                if (cellIndex === 0 && cellEl.classList.contains('day-label')) {
                    normalizeDayLabelCell(cellEl);
                    return;
                }

                if (cellEl.classList.contains('slot-empty-cell') || cellEl.classList.contains('slot-closed-cell')) {
                    replaceCellContents(cellEl, '');
                    return;
                }

                if (cellEl.classList.contains('slot-time-cell')) {
                    const staticValue = cellEl.querySelector('.slot-cell-static');
                    replaceCellContents(cellEl, textOrEmpty(staticValue && staticValue.textContent));
                    return;
                }

                if (cellEl.classList.contains('slot-staff-cell')) {
                    const staticValue = cellEl.querySelector('.slot-cell-static');
                    replaceCellContents(cellEl, textOrEmpty(staticValue && staticValue.textContent));
                    return;
                }

                if (cellEl.classList.contains('slot-shift-type-cell')) {
                    const staticValue = cellEl.querySelector('.slot-cell-static');
                    replaceCellContents(cellEl, textOrEmpty(staticValue && staticValue.textContent));
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
        if (!(surfaceEl instanceof HTMLElement) || !(tableEl instanceof HTMLElement)) {
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

        tableEl.querySelectorAll('.day-row, tbody tr').forEach(function (rowEl) {
            if (!(rowEl instanceof HTMLElement)) return;

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

        tableEl.querySelectorAll('[role="gridcell"], tbody td').forEach(function (cellEl) {
            if (!(cellEl instanceof HTMLElement)) return;

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
        if (!(rosterTable instanceof HTMLElement)) {
            throw new Error('Could not find the current roster grid.');
        }

        const exportTable = normalizeExportTable(rosterTable.cloneNode(true));
        const stageEl = document.createElement('div');
        stageEl.className = 'roster-export-stage';

        const surfaceEl = document.createElement('div');
        surfaceEl.className = 'roster-export-surface';
        const measuredWidth = Math.ceil(rosterTable.getBoundingClientRect().width);
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

        const formatKey = buttonEl.dataset.rosterExportFormat || 'jpg';
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

enableRosterStaffPanelSorting();

(function enableRosterStaffShiftHighlight() {
    if (typeof window === 'undefined') return;

    const rosterStaffRowSelector = '.roster-staff-panel-entry[data-roster-staff-id]';
    const rowHighlightClass = 'is-roster-staff-highlighted';
    const slotHighlightClass = 'is-roster-staff-slot-highlighted';
    const slotHighlightStartClass = 'is-roster-staff-slot-highlighted-start';
    const slotHighlightEndClass = 'is-roster-staff-slot-highlighted-end';
    const highlightClasses = [
        rowHighlightClass,
        slotHighlightClass,
        slotHighlightStartClass,
        slotHighlightEndClass,
    ];
    let hoverRosterStaffId = '';
    let pinnedRosterStaffId = '';

    function clearRosterStaffHighlights() {
        const selector = highlightClasses.map((className) => `.${className}`).join(', ');

        document.querySelectorAll(selector).forEach(function (element) {
            element.classList.remove(...highlightClasses);
        });
    }

    function highlightSlotElements(elements) {
        const slotElementsById = new Map();

        elements.forEach(function (element) {
            const slotId = element.dataset.rosterSlotId || '';
            if (!slotId) return;

            const slotElements = slotElementsById.get(slotId) || [];
            slotElements.push(element);
            slotElementsById.set(slotId, slotElements);
        });

        slotElementsById.forEach(function (slotElements) {
            slotElements.forEach(function (element, index) {
                element.classList.add(slotHighlightClass);
                if (index === 0) element.classList.add(slotHighlightStartClass);
                if (index === slotElements.length - 1) element.classList.add(slotHighlightEndClass);
            });
        });
    }

    function staffElements(selector, staffId) {
        return Array.from(document.querySelectorAll(selector)).filter(function (element) {
            return element instanceof HTMLElement && element.dataset.rosterStaffId === staffId;
        });
    }

    function staffRowFromEvent(event) {
        if (!(event.target instanceof Element)) return null;

        const row = event.target.closest(rosterStaffRowSelector);
        return row instanceof HTMLElement ? row : null;
    }

    function movedWithinRow(event, row) {
        return event.relatedTarget instanceof Node && row.contains(event.relatedTarget);
    }

    function syncLocateButtons() {
        document.querySelectorAll('[data-roster-staff-highlight-toggle="true"]').forEach(function (button) {
            if (!(button instanceof HTMLElement)) return;

            const row = button.closest(rosterStaffRowSelector);
            const isPressed = Boolean(row && row.dataset.rosterStaffId === pinnedRosterStaffId);
            button.setAttribute('aria-pressed', isPressed ? 'true' : 'false');
        });
    }

    function highlightRosterStaff(staffId) {
        clearRosterStaffHighlights();

        if (!staffId) {
            syncLocateButtons();
            return;
        }

        staffElements(rosterStaffRowSelector, staffId).forEach(function (element) {
            element.classList.add(rowHighlightClass);
        });

        highlightSlotElements(staffElements('.roster-grid [role="gridcell"][data-roster-staff-id][data-roster-slot-id]', staffId));
        highlightSlotElements(staffElements('.roster-shift-card[data-roster-staff-id][data-roster-slot-id]', staffId));
        syncLocateButtons();
    }

    function refreshRosterStaffHighlight() {
        highlightRosterStaff(pinnedRosterStaffId || hoverRosterStaffId);
    }

    function activateRosterStaff(row) {
        const staffId = row.dataset.rosterStaffId || '';
        if (!staffId) return;

        hoverRosterStaffId = staffId;
        refreshRosterStaffHighlight();
    }

    function deactivateRosterStaff(row) {
        const staffId = row.dataset.rosterStaffId || '';
        if (!staffId || staffId !== hoverRosterStaffId) {
            return;
        }

        hoverRosterStaffId = '';
        refreshRosterStaffHighlight();
    }

    function togglePinnedRosterStaff(row) {
        const staffId = row.dataset.rosterStaffId || '';
        if (!staffId) return;

        if (pinnedRosterStaffId === staffId) {
            pinnedRosterStaffId = '';
            hoverRosterStaffId = '';
        } else {
            pinnedRosterStaffId = staffId;
        }

        refreshRosterStaffHighlight();
    }

    const shiftGroupHighlightClass = 'is-roster-shift-group-highlighted';

    function shiftLauncherFromEvent(event) {
        if (!(event.target instanceof Element)) return null;

        const launcher = event.target.closest('[data-roster-shift-group-key]');
        return launcher instanceof HTMLElement ? launcher : null;
    }

    function movedWithinShiftGroup(event, launcher) {
        const groupKey = launcher.dataset.rosterShiftGroupKey || '';
        if (!groupKey || !(event.relatedTarget instanceof Element)) return false;

        const nextLauncher = event.relatedTarget.closest('[data-roster-shift-group-key]');
        return nextLauncher instanceof HTMLElement && nextLauncher.dataset.rosterShiftGroupKey === groupKey;
    }

    function setShiftGroupHighlight(groupKey, shouldHighlight) {
        if (!groupKey) return;

        document.querySelectorAll(`[data-roster-shift-group-key="${CSS.escape(groupKey)}"]`).forEach(function (element) {
            element.classList.toggle(shiftGroupHighlightClass, shouldHighlight);
        });
    }

    function handleShiftGroupEnter(event) {
        const launcher = shiftLauncherFromEvent(event);
        if (!launcher || movedWithinShiftGroup(event, launcher)) return;

        setShiftGroupHighlight(launcher.dataset.rosterShiftGroupKey || '', true);
    }

    function handleShiftGroupLeave(event) {
        const launcher = shiftLauncherFromEvent(event);
        if (!launcher || movedWithinShiftGroup(event, launcher)) return;

        setShiftGroupHighlight(launcher.dataset.rosterShiftGroupKey || '', false);
    }

    function handleShiftLauncherKeydown(event) {
        const launcher = shiftLauncherFromEvent(event);
        if (!launcher || event.target !== launcher || (event.key !== 'Enter' && event.key !== ' ')) return;

        event.preventDefault();
        launcher.click();
    }

    function handleStaffRowEnter(event) {
        const row = staffRowFromEvent(event);
        if (!row || movedWithinRow(event, row)) return;

        activateRosterStaff(row);
    }

    function handleStaffRowLeave(event) {
        const row = staffRowFromEvent(event);
        if (!row || movedWithinRow(event, row)) return;

        deactivateRosterStaff(row);
    }

    document.addEventListener('mouseover', handleShiftGroupEnter);
    document.addEventListener('mouseout', handleShiftGroupLeave);
    document.addEventListener('focusin', handleShiftGroupEnter);
    document.addEventListener('focusout', handleShiftGroupLeave);
    document.addEventListener('keydown', handleShiftLauncherKeydown);

    document.addEventListener('mouseover', handleStaffRowEnter);
    document.addEventListener('mouseout', handleStaffRowLeave);
    document.addEventListener('focusin', function (event) {
        const row = staffRowFromEvent(event);
        if (!row) return;

        activateRosterStaff(row);
    });

    document.addEventListener('focusout', function (event) {
        const row = staffRowFromEvent(event);
        if (!row || movedWithinRow(event, row)) return;

        deactivateRosterStaff(row);
    });

    document.addEventListener('click', function (event) {
        const toggleButton = event.target.closest('[data-roster-staff-highlight-toggle="true"]');
        if (!(toggleButton instanceof HTMLElement)) return;

        const row = toggleButton.closest(rosterStaffRowSelector);
        if (!(row instanceof HTMLElement)) return;

        event.preventDefault();
        event.stopPropagation();
        togglePinnedRosterStaff(row);
    }, true);

    document.addEventListener('keydown', function (event) {
        const row = staffRowFromEvent(event);
        if (!row || event.target !== row || (event.key !== 'Enter' && event.key !== ' ')) return;

        event.preventDefault();
        row.click();
    });

    document.addEventListener('app:page-ready', function () {
        if (pinnedRosterStaffId && !staffElements(rosterStaffRowSelector, pinnedRosterStaffId).length) {
            pinnedRosterStaffId = '';
        }

        refreshRosterStaffHighlight();
    });
})();
