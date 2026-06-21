import { compareRosterStaffData, type RosterStaffSortDirection, type RosterStaffSortKey } from "./staff-sort";

function rowSortData(row: HTMLElement) {
    return {
        name: row.dataset.rosterStaffName,
        assigned: row.dataset.rosterStaffAssigned,
        ideal: row.dataset.rosterStaffIdeal,
        role: row.dataset.rosterStaffRole,
    };
}

function compareRows(leftRow: HTMLElement, rightRow: HTMLElement, key: RosterStaffSortKey, direction: RosterStaffSortDirection): number {
    return compareRosterStaffData(rowSortData(leftRow), rowSortData(rightRow), key, direction);
}

function normalizeSortDirection(value: string | undefined): RosterStaffSortDirection {
    return value === "descending" ? "descending" : "ascending";
}

function syncSortButtonStates(tableEl: HTMLTableElement, activeKey: string, direction: RosterStaffSortDirection): void {
    tableEl.querySelectorAll('[data-roster-staff-sort-key]').forEach((buttonEl) => {
        if (!(buttonEl instanceof HTMLButtonElement)) return;

        const isActive = buttonEl.dataset.rosterStaffSortKey === activeKey;
        buttonEl.setAttribute("aria-sort", isActive ? direction : "none");

        const headerCell = buttonEl.closest("th");
        if (headerCell instanceof HTMLTableCellElement) {
            headerCell.setAttribute("aria-sort", isActive ? direction : "none");
        }
    });
}

function sortRosterStaffTable(tableEl: HTMLTableElement, key: string, direction: RosterStaffSortDirection): void {
    const tbodyEl = tableEl.querySelector(".roster-staff-table-body");
    if (!(tbodyEl instanceof HTMLTableSectionElement)) return;

    const rows = Array.from(tbodyEl.querySelectorAll(".roster-staff-panel-entry"))
        .filter((rowEl): rowEl is HTMLElement => rowEl instanceof HTMLElement);
    rows.sort((leftRow, rightRow) => compareRows(leftRow, rightRow, key, direction));
    rows.forEach((rowEl) => {
        tbodyEl.appendChild(rowEl);
    });

    tableEl.dataset.rosterStaffSortKey = key;
    tableEl.dataset.rosterStaffSortDirection = direction;
    syncSortButtonStates(tableEl, key, direction);
}

function nextDirection(tableEl: HTMLTableElement, key: string): RosterStaffSortDirection {
    const currentKey = tableEl.dataset.rosterStaffSortKey || "";
    const currentDirection = tableEl.dataset.rosterStaffSortDirection || "none";

    if (currentKey === key && currentDirection === "ascending") {
        return "descending";
    }

    return "ascending";
}

function initRosterStaffPanelSortingWithin(root: Document | Element): void {
    root.querySelectorAll(".roster-staff-table").forEach((tableEl) => {
        if (!(tableEl instanceof HTMLTableElement)) return;

        const defaultKey = tableEl.dataset.rosterStaffSortKey || "name";
        const defaultDirection = normalizeSortDirection(tableEl.dataset.rosterStaffSortDirection);
        sortRosterStaffTable(tableEl, defaultKey, defaultDirection);
    });
}

type PageReadyEvent = Event & {
    detail?: {
        target?: unknown;
    };
};

function rootFromPageReadyEvent(event: Event): Document | Element {
    const target = (event as PageReadyEvent).detail?.target;
    return target instanceof Element || target instanceof Document ? target : document;
}

export function enableRosterStaffPanelSorting(): void {
    if (typeof window === "undefined") return;

    document.addEventListener("click", (event) => {
        if (!(event.target instanceof Element)) return;

        const buttonEl = event.target.closest('[data-roster-staff-sort-key]');
        if (!(buttonEl instanceof HTMLButtonElement)) return;

        const tableEl = buttonEl.closest(".roster-staff-table");
        if (!(tableEl instanceof HTMLTableElement)) return;

        const key = buttonEl.dataset.rosterStaffSortKey || "name";
        const direction = nextDirection(tableEl, key);
        sortRosterStaffTable(tableEl, key, direction);
    });

    document.addEventListener("app:page-ready", (event) => {
        initRosterStaffPanelSortingWithin(rootFromPageReadyEvent(event));
    });
}
