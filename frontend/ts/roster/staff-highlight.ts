import { onAppPageReady } from "../shared/lifecycle";

const rosterStaffRowSelector = ".roster-staff-panel-entry[data-roster-staff-id]";
const rowHighlightClass = "is-roster-staff-highlighted";
const slotHighlightClass = "is-roster-staff-slot-highlighted";
const slotHighlightStartClass = "is-roster-staff-slot-highlighted-start";
const slotHighlightEndClass = "is-roster-staff-slot-highlighted-end";
const highlightClasses = [
    rowHighlightClass,
    slotHighlightClass,
    slotHighlightStartClass,
    slotHighlightEndClass,
];
const shiftGroupHighlightClass = "is-roster-shift-group-highlighted";

let hoverRosterStaffId = "";
let pinnedRosterStaffId = "";

function clearRosterStaffHighlights(): void {
    const selector = highlightClasses.map((className) => `.${className}`).join(", ");

    document.querySelectorAll(selector).forEach((element) => {
        element.classList.remove(...highlightClasses);
    });
}

function highlightSlotElements(elements: HTMLElement[]): void {
    const slotElementsById = new Map<string, HTMLElement[]>();

    elements.forEach((element) => {
        const slotId = element.dataset.rosterSlotId || "";
        if (!slotId) return;

        const slotElements = slotElementsById.get(slotId) || [];
        slotElements.push(element);
        slotElementsById.set(slotId, slotElements);
    });

    slotElementsById.forEach((slotElements) => {
        slotElements.forEach((element, index) => {
            element.classList.add(slotHighlightClass);
            if (index === 0) element.classList.add(slotHighlightStartClass);
            if (index === slotElements.length - 1) element.classList.add(slotHighlightEndClass);
        });
    });
}

function staffElements(selector: string, staffId: string): HTMLElement[] {
    return Array.from(document.querySelectorAll(selector)).filter(
        (element): element is HTMLElement => element instanceof HTMLElement && element.dataset.rosterStaffId === staffId,
    );
}

function staffRowFromEvent(event: Event): HTMLElement | null {
    if (!(event.target instanceof Element)) return null;

    const row = event.target.closest(rosterStaffRowSelector);
    return row instanceof HTMLElement ? row : null;
}

function movedWithinRow(event: MouseEvent | FocusEvent, row: HTMLElement): boolean {
    return event.relatedTarget instanceof Node && row.contains(event.relatedTarget);
}

function syncLocateButtons(): void {
    document.querySelectorAll('[data-roster-staff-highlight-toggle="true"]').forEach((button) => {
        if (!(button instanceof HTMLElement)) return;

        const row = button.closest(rosterStaffRowSelector);
        const isPressed = Boolean(row instanceof HTMLElement && row.dataset.rosterStaffId === pinnedRosterStaffId);
        button.setAttribute("aria-pressed", isPressed ? "true" : "false");
    });
}

function highlightRosterStaff(staffId: string): void {
    clearRosterStaffHighlights();

    if (!staffId) {
        syncLocateButtons();
        return;
    }

    staffElements(rosterStaffRowSelector, staffId).forEach((element) => {
        element.classList.add(rowHighlightClass);
    });

    highlightSlotElements(staffElements('.roster-grid [role="gridcell"][data-roster-staff-id][data-roster-slot-id]', staffId));
    highlightSlotElements(staffElements(".roster-shift-card[data-roster-staff-id][data-roster-slot-id]", staffId));
    syncLocateButtons();
}

function refreshRosterStaffHighlight(): void {
    highlightRosterStaff(pinnedRosterStaffId || hoverRosterStaffId);
}

function activateRosterStaff(row: HTMLElement): void {
    const staffId = row.dataset.rosterStaffId || "";
    if (!staffId) return;

    hoverRosterStaffId = staffId;
    refreshRosterStaffHighlight();
}

function deactivateRosterStaff(row: HTMLElement): void {
    const staffId = row.dataset.rosterStaffId || "";
    if (!staffId || staffId !== hoverRosterStaffId) {
        return;
    }

    hoverRosterStaffId = "";
    refreshRosterStaffHighlight();
}

function togglePinnedRosterStaff(row: HTMLElement): void {
    const staffId = row.dataset.rosterStaffId || "";
    if (!staffId) return;

    if (pinnedRosterStaffId === staffId) {
        pinnedRosterStaffId = "";
        hoverRosterStaffId = "";
    } else {
        pinnedRosterStaffId = staffId;
    }

    refreshRosterStaffHighlight();
}

function shiftLauncherFromEvent(event: Event): HTMLElement | null {
    if (!(event.target instanceof Element)) return null;

    const launcher = event.target.closest('[data-roster-shift-group-key]');
    return launcher instanceof HTMLElement ? launcher : null;
}

function movedWithinShiftGroup(event: MouseEvent | FocusEvent, launcher: HTMLElement): boolean {
    const groupKey = launcher.dataset.rosterShiftGroupKey || "";
    if (!groupKey || !(event.relatedTarget instanceof Element)) return false;

    const nextLauncher = event.relatedTarget.closest('[data-roster-shift-group-key]');
    return nextLauncher instanceof HTMLElement && nextLauncher.dataset.rosterShiftGroupKey === groupKey;
}

function setShiftGroupHighlight(groupKey: string, shouldHighlight: boolean): void {
    if (!groupKey) return;

    document.querySelectorAll(`[data-roster-shift-group-key="${CSS.escape(groupKey)}"]`).forEach((element) => {
        element.classList.toggle(shiftGroupHighlightClass, shouldHighlight);
    });
}

function handleShiftGroupEnter(event: MouseEvent | FocusEvent): void {
    const launcher = shiftLauncherFromEvent(event);
    if (!launcher || movedWithinShiftGroup(event, launcher)) return;

    setShiftGroupHighlight(launcher.dataset.rosterShiftGroupKey || "", true);
}

function handleShiftGroupLeave(event: MouseEvent | FocusEvent): void {
    const launcher = shiftLauncherFromEvent(event);
    if (!launcher || movedWithinShiftGroup(event, launcher)) return;

    setShiftGroupHighlight(launcher.dataset.rosterShiftGroupKey || "", false);
}

function handleShiftLauncherKeydown(event: KeyboardEvent): void {
    const launcher = shiftLauncherFromEvent(event);
    if (!launcher || event.target !== launcher || (event.key !== "Enter" && event.key !== " ")) return;

    event.preventDefault();
    launcher.click();
}

function handleStaffRowEnter(event: MouseEvent): void {
    const row = staffRowFromEvent(event);
    if (!row || movedWithinRow(event, row)) return;

    activateRosterStaff(row);
}

function handleStaffRowLeave(event: MouseEvent): void {
    const row = staffRowFromEvent(event);
    if (!row || movedWithinRow(event, row)) return;

    deactivateRosterStaff(row);
}

export function enableRosterStaffShiftHighlight(): void {
    if (typeof window === "undefined") return;

    document.addEventListener("mouseover", handleShiftGroupEnter);
    document.addEventListener("mouseout", handleShiftGroupLeave);
    document.addEventListener("focusin", handleShiftGroupEnter);
    document.addEventListener("focusout", handleShiftGroupLeave);
    document.addEventListener("keydown", handleShiftLauncherKeydown);

    document.addEventListener("mouseover", handleStaffRowEnter);
    document.addEventListener("mouseout", handleStaffRowLeave);
    document.addEventListener("focusin", (event) => {
        const row = staffRowFromEvent(event);
        if (!row) return;

        activateRosterStaff(row);
    });

    document.addEventListener("focusout", (event) => {
        const row = staffRowFromEvent(event);
        if (!row || movedWithinRow(event, row)) return;

        deactivateRosterStaff(row);
    });

    document.addEventListener("pointerdown", (event) => {
        if (!(event.target instanceof Element)) return;
        if (!event.target.closest('[data-roster-staff-row-action-ignore="true"]')) return;

        event.stopImmediatePropagation();
    }, true);

    document.addEventListener("click", (event) => {
        if (!(event.target instanceof Element)) return;

        const toggleButton = event.target.closest('[data-roster-staff-highlight-toggle="true"]');
        if (!(toggleButton instanceof HTMLElement)) return;

        const row = toggleButton.closest(rosterStaffRowSelector);
        if (!(row instanceof HTMLElement)) return;

        event.preventDefault();
        event.stopPropagation();
        togglePinnedRosterStaff(row);
    }, true);

    document.addEventListener("keydown", (event) => {
        const row = staffRowFromEvent(event);
        if (!row || event.target !== row || (event.key !== "Enter" && event.key !== " ")) return;

        event.preventDefault();
        row.click();
    });

    onAppPageReady(() => {
        if (pinnedRosterStaffId && !staffElements(rosterStaffRowSelector, pinnedRosterStaffId).length) {
            pinnedRosterStaffId = "";
        }

        refreshRosterStaffHighlight();
    });
}
