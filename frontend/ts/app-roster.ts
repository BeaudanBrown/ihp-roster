// @ts-nocheck

import { enableRosterColumnEditMode } from "./roster/column-edit";
import { rosterFullscreenLabels } from "./roster/fullscreen";
import { enableRosterImageExport } from "./roster/image-export";
import { rosterOverviewSummaryFromDayDataset } from "./roster/overview";
import { enableRosterStaffShiftHighlight } from "./roster/staff-highlight";
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

enableRosterImageExport();

enableRosterStaffPanelSorting();

enableRosterStaffShiftHighlight();
