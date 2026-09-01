import {
    rosterWeekOverviewAssignedValueDomAttr,
    rosterWeekOverviewAvailabilityDomAttr,
    rosterWeekOverviewAvailabilityStates,
    rosterWeekOverviewCalendarDayDomAttr,
    rosterWeekOverviewCalendarDayStates,
    rosterWeekOverviewClosureDomAttr,
    rosterWeekOverviewClosureStates,
    rosterWeekOverviewDayDomAttr,
    rosterWeekOverviewDetailsDomAttr,
    rosterWeekOverviewGoLinkDomAttr,
    rosterWeekOverviewHoursValueDomAttr,
    rosterWeekOverviewLeaveValueDomAttr,
    rosterWeekOverviewPanelDomAttr,
    rosterWeekOverviewSelectedLabelDomAttr,
    rosterWeekOverviewSummaryDomAttr,
    rosterWeekOverviewWeekLabelDomAttr,
} from "../generated/contracts";
import {
    parseRosterWeekOverviewDayConfiguration,
    parseRosterWeekOverviewPanelConfiguration,
} from "../roster/week-overview-configuration";
import {
    updateRosterWeekOverviewSelection,
    type RosterWeekOverviewDiagnostic,
} from "../roster/week-overview";
import { assertDeepEqual, assertEqual, assertThrows, test } from "./harness";
import { MiniElement as SharedMiniElement } from "./mini-dom";

const validDay = {
    weekOverviewDate: "2025-01-06",
    weekOverviewSelectedLabel: "Mon 6 Jan",
    weekOverviewLeaveDisplay: "2",
    weekOverviewAssignedDisplay: "5",
    weekOverviewHoursDisplay: "30h",
    weekOverviewSummaryText: "2 unavailable periods, 5 shifts assigned, 30h rostered.",
    weekOverviewWeekLabel: "In Week of 6 Jan",
    weekOverviewNavigationUrl: "/ShowRosterWindow?anchorDate=2025-01-06",
    weekOverviewAvailability: rosterWeekOverviewAvailabilityStates.loaded,
    weekOverviewClosure: rosterWeekOverviewClosureStates.closed,
};

class MiniElement extends SharedMiniElement {
    href = "";

    constructor(attrs: Record<string, string>, tagName = "DIV", id = "") {
        super(attrs, id, [], tagName);
    }
}

function roleSlot(attribute: string, tagName = "DIV"): MiniElement {
    return new MiniElement({ [attribute]: "true" }, tagName);
}

test("roster week overview parses exact Haskell-owned panel and day payloads", () => {
    assertDeepEqual(
        parseRosterWeekOverviewPanelConfiguration('{"weekOverviewCurrentDate":"2025-01-06"}'),
        { weekOverviewCurrentDate: "2025-01-06" },
    );
    assertDeepEqual(
        parseRosterWeekOverviewDayConfiguration(JSON.stringify(validDay)),
        validDay,
    );
    assertThrows(
        () => parseRosterWeekOverviewDayConfiguration(JSON.stringify({ ...validDay, assigned: "5" })),
        "Invalid RosterWeekOverviewDayConfig",
    );
});

test("roster week overview rejects payload states outside the generated inventories", () => {
    assertThrows(
        () => parseRosterWeekOverviewDayConfiguration(JSON.stringify({ ...validDay, weekOverviewAvailability: "pending" })),
        "availability state",
    );
    assertThrows(
        () => parseRosterWeekOverviewDayConfiguration(JSON.stringify({ ...validDay, weekOverviewClosure: "holiday" })),
        "closure state",
    );
    assertThrows(
        () => parseRosterWeekOverviewPanelConfiguration('{"weekOverviewCurrentDate":"2025-01-06","fallbackDate":"2025-01-01"}'),
        "Invalid RosterWeekOverviewPanelConfig",
    );
});

test("roster week overview rejects only a malformed day and reports structured diagnostics", () => {
    const panel = new MiniElement({
        [rosterWeekOverviewPanelDomAttr]: '{"weekOverviewCurrentDate":"2025-01-06"}',
    }, "DIV", "overview-panel");
    const valid = panel.append(new MiniElement({
        [rosterWeekOverviewDayDomAttr]: JSON.stringify(validDay),
        [rosterWeekOverviewAvailabilityDomAttr]: rosterWeekOverviewAvailabilityStates.loaded,
        [rosterWeekOverviewClosureDomAttr]: rosterWeekOverviewClosureStates.closed,
        [rosterWeekOverviewCalendarDayDomAttr]: rosterWeekOverviewCalendarDayStates.today,
        "aria-pressed": "false",
    }, "BUTTON", "valid-day"));
    const malformed = panel.append(new MiniElement({
        [rosterWeekOverviewDayDomAttr]: "not-json",
        [rosterWeekOverviewAvailabilityDomAttr]: rosterWeekOverviewAvailabilityStates.unloaded,
        [rosterWeekOverviewClosureDomAttr]: rosterWeekOverviewClosureStates.open,
        [rosterWeekOverviewCalendarDayDomAttr]: rosterWeekOverviewCalendarDayStates["other-day"],
        "aria-pressed": "true",
    }, "BUTTON", "malformed-day"));

    const selectedLabel = panel.append(roleSlot(rosterWeekOverviewSelectedLabelDomAttr));
    const leave = panel.append(roleSlot(rosterWeekOverviewLeaveValueDomAttr));
    const assigned = panel.append(roleSlot(rosterWeekOverviewAssignedValueDomAttr));
    const hours = panel.append(roleSlot(rosterWeekOverviewHoursValueDomAttr));
    const summary = panel.append(roleSlot(rosterWeekOverviewSummaryDomAttr));
    const weekLabel = panel.append(roleSlot(rosterWeekOverviewWeekLabelDomAttr));
    const goLink = panel.append(roleSlot(rosterWeekOverviewGoLinkDomAttr, "A"));
    const details = panel.append(new MiniElement({
        [rosterWeekOverviewDetailsDomAttr]: "true",
        [rosterWeekOverviewAvailabilityDomAttr]: rosterWeekOverviewAvailabilityStates.loaded,
        [rosterWeekOverviewClosureDomAttr]: rosterWeekOverviewClosureStates.open,
    }));
    const diagnostics: RosterWeekOverviewDiagnostic[] = [];

    assertEqual(
        updateRosterWeekOverviewSelection(
            panel as unknown as HTMLElement,
            valid as unknown as HTMLElement,
            (diagnostic) => diagnostics.push(diagnostic),
        ),
        true,
    );
    assertEqual(valid.getAttribute("aria-pressed"), "true");
    assertEqual(malformed.getAttribute("aria-pressed"), "true");
    assertEqual(selectedLabel.textContent, validDay.weekOverviewSelectedLabel);
    assertEqual(leave.textContent, validDay.weekOverviewLeaveDisplay);
    assertEqual(assigned.textContent, validDay.weekOverviewAssignedDisplay);
    assertEqual(hours.textContent, validDay.weekOverviewHoursDisplay);
    assertEqual(summary.textContent, validDay.weekOverviewSummaryText);
    assertEqual(weekLabel.textContent, validDay.weekOverviewWeekLabel);
    assertEqual(goLink.href, validDay.weekOverviewNavigationUrl);
    assertEqual(details.getAttribute(rosterWeekOverviewClosureDomAttr), rosterWeekOverviewClosureStates.closed);
    assertDeepEqual(diagnostics.map((diagnostic) => diagnostic.code), ["invalid-day-config"]);

    assertEqual(
        updateRosterWeekOverviewSelection(
            panel as unknown as HTMLElement,
            malformed as unknown as HTMLElement,
            (diagnostic) => diagnostics.push(diagnostic),
        ),
        false,
    );
    assertEqual(summary.textContent, validDay.weekOverviewSummaryText);
    assertDeepEqual(diagnostics.map((diagnostic) => diagnostic.code), ["invalid-day-config", "invalid-day-config"]);
});
