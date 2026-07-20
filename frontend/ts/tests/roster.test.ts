import { rosterFullscreenLabels } from "../roster/fullscreen";
import { rosterOverviewSummaryFromDayDataset } from "../roster/overview";
import { assertDeepEqual, test } from "./harness";

test("roster overview summary preserves loaded and unloaded day values", () => {
    assertDeepEqual(rosterOverviewSummaryFromDayDataset({
        weekOverviewDetails: "true",
        weekOverviewClosed: "false",
        weekOverviewLabel: "Mon 1 Jan",
        weekOverviewLeave: "2",
        weekOverviewAssigned: "5",
        weekOverviewHours: "30h",
        weekOverviewSummary: "5 assigned",
        weekOverviewWeekLabel: "This week",
        weekOverviewUrl: "/ShowRosterWeek#day-1",
    }), {
        hasDetails: true,
        isClosed: false,
        label: "Mon 1 Jan",
        leave: "2",
        assigned: "5",
        hours: "30h",
        summary: "5 assigned",
        weekLabel: "In This week",
        url: "/ShowRosterWeek#day-1",
    });

    assertDeepEqual(rosterOverviewSummaryFromDayDataset({ weekOverviewDetails: "false" }), {
        hasDetails: false,
        isClosed: false,
        label: "",
        leave: "—",
        assigned: "—",
        hours: "—",
        summary: "",
        weekLabel: "In ",
        url: "",
    });
});

test("roster fullscreen labels preserve aria and icon state", () => {
    assertDeepEqual(rosterFullscreenLabels(false), {
        pressed: "false",
        label: "Expand roster",
        iconAdd: "bi-fullscreen",
        iconRemove: "bi-fullscreen-exit",
    });
    assertDeepEqual(rosterFullscreenLabels(true), {
        pressed: "true",
        label: "Exit expanded roster",
        iconAdd: "bi-fullscreen-exit",
        iconRemove: "bi-fullscreen",
    });
});
