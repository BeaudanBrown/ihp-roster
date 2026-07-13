import { onAppPageReady } from "../shared/lifecycle";

type RosterStaffPanelTab = "staff" | "settings";

const tabSelector = '[data-roster-staff-panel-tab]';
let activeTab: RosterStaffPanelTab = "staff";

function tabValue(element: Element): RosterStaffPanelTab | null {
    if (!(element instanceof HTMLElement)) return null;
    const value = element.dataset.rosterStaffPanelTab;
    return value === "staff" || value === "settings" ? value : null;
}

function restoreActiveTab(): void {
    if (activeTab === "staff") return;

    const tab = Array.from(document.querySelectorAll(tabSelector))
        .find((candidate) => tabValue(candidate) === activeTab);
    if (!(tab instanceof HTMLElement)) return;

    window.bootstrap?.Tab?.getOrCreateInstance(tab).show();
}

export function enableRosterStaffPanelTabs(): void {
    if (typeof window === "undefined") return;

    document.addEventListener("click", (event) => {
        if (!(event.target instanceof Element)) return;
        const tab = event.target.closest(tabSelector);
        const value = tabValue(tab ?? event.target);
        if (value !== null) activeTab = value;
    });

    onAppPageReady(restoreActiveTab);
}
