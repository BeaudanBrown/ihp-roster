import {
    isRosterWeekOverviewAvailabilityState,
    isRosterWeekOverviewCalendarDayState,
    isRosterWeekOverviewClosureState,
    rosterWeekOverviewAssignedValueDomAttr,
    rosterWeekOverviewAvailabilityDomAttr,
    rosterWeekOverviewCalendarDayDomAttr,
    rosterWeekOverviewCalendarDayStates,
    rosterWeekOverviewClosureDomAttr,
    rosterWeekOverviewDayDomAttr,
    rosterWeekOverviewDetailsDomAttr,
    rosterWeekOverviewGoLinkDomAttr,
    rosterWeekOverviewHoursValueDomAttr,
    rosterWeekOverviewLeaveValueDomAttr,
    rosterWeekOverviewPanelDomAttr,
    rosterWeekOverviewSelectedLabelDomAttr,
    rosterWeekOverviewSummaryDomAttr,
    rosterWeekOverviewTodayDomAttr,
    rosterWeekOverviewWeekLabelDomAttr,
    type RosterWeekOverviewDayConfig,
} from "../generated/contracts";
import {
    parseRosterWeekOverviewDayConfiguration,
    parseRosterWeekOverviewPanelConfiguration,
} from "./week-overview-configuration";

export type RosterWeekOverviewDiagnosticCode =
    | "invalid-panel-config"
    | "day-outside-panel"
    | "invalid-day-config"
    | "invalid-day-state"
    | "invalid-slot-count"
    | "invalid-slot-role"
    | "invalid-details-state"
    | "invalid-go-link"
    | "invalid-today-role"
    | "missing-today-day";

export type RosterWeekOverviewDiagnostic = {
    code: RosterWeekOverviewDiagnosticCode;
    elementId: string | null;
    message: string;
};

export type RosterWeekOverviewDiagnosticReporter = (
    diagnostic: RosterWeekOverviewDiagnostic,
) => void;

type RosterWeekOverviewSlots = {
    selectedLabel: HTMLElement;
    leaveValue: HTMLElement | null;
    assignedValue: HTMLElement;
    hoursValue: HTMLElement;
    summary: HTMLElement;
    weekLabel: HTMLElement;
    goLink: HTMLAnchorElement;
    details: HTMLElement;
};

const panelSelector = `[${rosterWeekOverviewPanelDomAttr}]`;
const daySelector = `[${rosterWeekOverviewDayDomAttr}]`;
const todaySelector = `[${rosterWeekOverviewTodayDomAttr}]`;

function roleSelector(attribute: string): string {
    return `[${attribute}]`;
}

function defaultDiagnosticReporter(diagnostic: RosterWeekOverviewDiagnostic): void {
    console.error?.("Invalid generated roster week-overview boundary", diagnostic);
}

function diagnostic(
    element: Element,
    code: RosterWeekOverviewDiagnosticCode,
    message: string,
): RosterWeekOverviewDiagnostic {
    return { code, elementId: element.id || null, message };
}

function ownedElements<T extends Element>(panel: HTMLElement, attribute: string): T[] {
    return Array.from(panel.querySelectorAll<T>(roleSelector(attribute)))
        .filter((element) => element.closest(panelSelector) === panel);
}

function readPanel(
    panel: HTMLElement,
    report: RosterWeekOverviewDiagnosticReporter,
): ReturnType<typeof parseRosterWeekOverviewPanelConfiguration> | null {
    try {
        const raw = panel.getAttribute(rosterWeekOverviewPanelDomAttr);
        if (raw === null) throw new Error(`Missing ${rosterWeekOverviewPanelDomAttr}`);
        return parseRosterWeekOverviewPanelConfiguration(raw);
    } catch (error) {
        report(diagnostic(
            panel,
            "invalid-panel-config",
            error instanceof Error ? error.message : String(error),
        ));
        return null;
    }
}

function readDay(
    day: HTMLElement,
    report: RosterWeekOverviewDiagnosticReporter,
): RosterWeekOverviewDayConfig | null {
    try {
        const raw = day.getAttribute(rosterWeekOverviewDayDomAttr);
        if (raw === null) throw new Error(`Missing ${rosterWeekOverviewDayDomAttr}`);
        const config = parseRosterWeekOverviewDayConfiguration(raw);
        const calendarDay = day.getAttribute(rosterWeekOverviewCalendarDayDomAttr);
        const calendarDayIsDeclared = isRosterWeekOverviewCalendarDayState(calendarDay)
            && (calendarDay === rosterWeekOverviewCalendarDayStates.today
                || calendarDay === rosterWeekOverviewCalendarDayStates["other-day"]);
        if (
            day.getAttribute(rosterWeekOverviewAvailabilityDomAttr) !== config.weekOverviewAvailability
            || day.getAttribute(rosterWeekOverviewClosureDomAttr) !== config.weekOverviewClosure
            || !calendarDayIsDeclared
        ) {
            report(diagnostic(day, "invalid-day-state", "Week-overview day states must agree with its exact payload"));
            return null;
        }
        return config;
    } catch (error) {
        report(diagnostic(
            day,
            "invalid-day-config",
            error instanceof Error ? error.message : String(error),
        ));
        return null;
    }
}

function readSingleSlot<T extends HTMLElement>(
    panel: HTMLElement,
    attribute: string,
    report: RosterWeekOverviewDiagnosticReporter,
): T | null {
    const slots = ownedElements<T>(panel, attribute);
    if (slots.length !== 1) {
        report(diagnostic(panel, "invalid-slot-count", `Week-overview panel requires exactly one ${attribute} slot`));
        return null;
    }
    const slot = slots[0];
    if (slot.getAttribute(attribute) !== "true") {
        report(diagnostic(slot, "invalid-slot-role", `Week-overview slot ${attribute} must equal true`));
        return null;
    }
    return slot;
}

function readOptionalSlot<T extends HTMLElement>(
    panel: HTMLElement,
    attribute: string,
    report: RosterWeekOverviewDiagnosticReporter,
): T | null | false {
    const slots = ownedElements<T>(panel, attribute);
    if (slots.length > 1) {
        report(diagnostic(panel, "invalid-slot-count", `Week-overview panel permits at most one ${attribute} slot`));
        return false;
    }
    const slot = slots[0] ?? null;
    if (slot !== null && slot.getAttribute(attribute) !== "true") {
        report(diagnostic(slot, "invalid-slot-role", `Week-overview slot ${attribute} must equal true`));
        return false;
    }
    return slot;
}

function readSlots(
    panel: HTMLElement,
    report: RosterWeekOverviewDiagnosticReporter,
): RosterWeekOverviewSlots | null {
    const selectedLabel = readSingleSlot(panel, rosterWeekOverviewSelectedLabelDomAttr, report);
    const leaveValue = readOptionalSlot(panel, rosterWeekOverviewLeaveValueDomAttr, report);
    const assignedValue = readSingleSlot(panel, rosterWeekOverviewAssignedValueDomAttr, report);
    const hoursValue = readSingleSlot(panel, rosterWeekOverviewHoursValueDomAttr, report);
    const summary = readSingleSlot(panel, rosterWeekOverviewSummaryDomAttr, report);
    const weekLabel = readSingleSlot(panel, rosterWeekOverviewWeekLabelDomAttr, report);
    const goLinkElement = readSingleSlot(panel, rosterWeekOverviewGoLinkDomAttr, report);
    const details = readSingleSlot(panel, rosterWeekOverviewDetailsDomAttr, report);

    if (
        selectedLabel === null
        || leaveValue === false
        || assignedValue === null
        || hoursValue === null
        || summary === null
        || weekLabel === null
        || goLinkElement === null
        || details === null
    ) return null;

    if (goLinkElement.tagName !== "A") {
        report(diagnostic(goLinkElement, "invalid-go-link", "Week-overview go-link slot must be an anchor"));
        return null;
    }
    if (
        !isRosterWeekOverviewAvailabilityState(details.getAttribute(rosterWeekOverviewAvailabilityDomAttr))
        || !isRosterWeekOverviewClosureState(details.getAttribute(rosterWeekOverviewClosureDomAttr))
    ) {
        report(diagnostic(details, "invalid-details-state", "Week-overview details states must be generated values"));
        return null;
    }

    return {
        selectedLabel,
        leaveValue,
        assignedValue,
        hoursValue,
        summary,
        weekLabel,
        goLink: goLinkElement as HTMLAnchorElement,
        details,
    };
}

export function updateRosterWeekOverviewSelection(
    panel: HTMLElement,
    selectedDay: HTMLElement,
    report: RosterWeekOverviewDiagnosticReporter = defaultDiagnosticReporter,
): boolean {
    if (selectedDay.closest(panelSelector) !== panel) {
        report(diagnostic(selectedDay, "day-outside-panel", "Week-overview day is not owned by this panel"));
        return false;
    }
    if (readPanel(panel, report) === null) return false;

    const selectedConfig = readDay(selectedDay, report);
    if (selectedConfig === null) return false;
    const slots = readSlots(panel, report);
    if (slots === null) return false;

    const validDays = new Map<HTMLElement, RosterWeekOverviewDayConfig>();
    for (const day of ownedElements<HTMLElement>(panel, rosterWeekOverviewDayDomAttr)) {
        const config = day === selectedDay ? selectedConfig : readDay(day, report);
        if (config !== null) validDays.set(day, config);
    }

    validDays.forEach((_config, day) => {
        day.setAttribute("aria-pressed", day === selectedDay ? "true" : "false");
    });
    slots.selectedLabel.textContent = selectedConfig.weekOverviewSelectedLabel;
    if (slots.leaveValue !== null) slots.leaveValue.textContent = selectedConfig.weekOverviewLeaveDisplay;
    slots.assignedValue.textContent = selectedConfig.weekOverviewAssignedDisplay;
    slots.hoursValue.textContent = selectedConfig.weekOverviewHoursDisplay;
    slots.summary.textContent = selectedConfig.weekOverviewSummaryText;
    slots.weekLabel.textContent = selectedConfig.weekOverviewWeekLabel;
    slots.goLink.href = selectedConfig.weekOverviewNavigationUrl;
    slots.details.setAttribute(rosterWeekOverviewAvailabilityDomAttr, selectedConfig.weekOverviewAvailability);
    slots.details.setAttribute(rosterWeekOverviewClosureDomAttr, selectedConfig.weekOverviewClosure);
    return true;
}

function selectToday(
    panel: HTMLElement,
    report: RosterWeekOverviewDiagnosticReporter,
): boolean {
    const panelConfig = readPanel(panel, report);
    if (panelConfig === null) return false;

    for (const day of ownedElements<HTMLElement>(panel, rosterWeekOverviewDayDomAttr)) {
        const config = readDay(day, report);
        if (config?.weekOverviewDate === panelConfig.weekOverviewCurrentDate) {
            return updateRosterWeekOverviewSelection(panel, day, report);
        }
    }
    report(diagnostic(panel, "missing-today-day", "Week-overview panel has no valid day for its Haskell-provided current date"));
    return false;
}

function panelForControl(control: Element): HTMLElement | null {
    const panel = control.closest(panelSelector);
    return panel instanceof HTMLElement ? panel : null;
}

export function enableRosterWeekOverview(
    report: RosterWeekOverviewDiagnosticReporter = defaultDiagnosticReporter,
): void {
    if (typeof window === "undefined") return;

    document.addEventListener("click", (event) => {
        if (!(event.target instanceof Element)) return;

        const day = event.target.closest(daySelector);
        if (day instanceof HTMLElement) {
            const panel = panelForControl(day);
            if (panel !== null) updateRosterWeekOverviewSelection(panel, day, report);
            return;
        }

        const today = event.target.closest(todaySelector);
        if (today instanceof HTMLElement) {
            if (today.getAttribute(rosterWeekOverviewTodayDomAttr) !== "true") {
                report(diagnostic(today, "invalid-today-role", "Week-overview today role must equal true"));
                return;
            }
            const panel = panelForControl(today);
            if (panel !== null) selectToday(panel, report);
        }
    });

    document.addEventListener("shown.bs.dropdown", (event) => {
        const trigger = event.target;
        if (!(trigger instanceof HTMLElement) || trigger.parentElement === null) return;
        const panels = Array.from(trigger.parentElement.querySelectorAll<HTMLElement>(panelSelector));
        const panel = panels.find((candidate) => candidate.closest(panelSelector) === candidate);
        if (panel === undefined) return;

        const selectedDay = ownedElements<HTMLElement>(panel, rosterWeekOverviewDayDomAttr)
            .find((day) => day.getAttribute("aria-pressed") === "true");
        if (selectedDay !== undefined) updateRosterWeekOverviewSelection(panel, selectedDay, report);
    });
}
