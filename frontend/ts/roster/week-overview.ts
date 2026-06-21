import { rosterOverviewSummaryFromDayDataset } from "./overview";

function updateOverviewSelection(panelEl: Element | null, dayButton: Element | null): void {
    if (!(panelEl instanceof HTMLElement) || !(dayButton instanceof HTMLElement)) return;

    panelEl.querySelectorAll('[data-week-overview-day="true"]').forEach((button) => {
        if (button instanceof HTMLElement) {
            button.classList.toggle("is-selected", button === dayButton);
            button.setAttribute("aria-pressed", button === dayButton ? "true" : "false");
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
        detailsPanel.classList.toggle("is-unloaded", !summary.hasDetails);
        detailsPanel.classList.toggle("is-closed", summary.isClosed);
    }
}

function selectToday(panelEl: Element | null): void {
    if (!(panelEl instanceof HTMLElement)) return;
    const today = panelEl.dataset.weekOverviewCurrentDate;
    if (!today) return;
    const button = panelEl.querySelector(`[data-week-overview-day="true"][data-week-overview-date="${CSS.escape(today)}"]`);
    if (button instanceof HTMLElement) {
        updateOverviewSelection(panelEl, button);
    }
}

export function enableRosterWeekOverview(): void {
    if (typeof window === "undefined") return;

    document.addEventListener("click", (event) => {
        if (!(event.target instanceof Element)) return;

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

    document.addEventListener("shown.bs.dropdown", (event) => {
        const trigger = event.target;
        if (!(trigger instanceof HTMLElement)) return;
        const panelEl = trigger.parentElement?.querySelector('[data-week-overview-panel="true"]');
        if (!(panelEl instanceof HTMLElement)) return;

        const selectedButton = panelEl.querySelector('[data-week-overview-day="true"].is-selected');
        if (selectedButton instanceof HTMLElement) {
            updateOverviewSelection(panelEl, selectedButton);
        }
    });
}
