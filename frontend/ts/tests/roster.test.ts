import { rosterFullscreenLabels } from "../roster/fullscreen";
import { rosterOverviewSummaryFromDayDataset } from "../roster/overview";
import { compareRosterStaffData, rosterParseNumber } from "../roster/staff-sort";
import { assertDeepEqual, assertEqual, test } from "./harness";

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

test("roster staff sorting helpers preserve numeric and text fallback ordering", () => {
    assertEqual(rosterParseNumber("7"), 7);
    assertEqual(rosterParseNumber("bad"), 0);

    const alex = { name: "Alex", assigned: "4", ideal: "5", role: "manager" };
    const blair = { name: "Blair", assigned: "2", ideal: "5", role: "worker" };
    assertEqual(compareRosterStaffData(alex, blair, "shifts", "ascending") > 0, true);
    assertEqual(compareRosterStaffData(alex, blair, "shifts", "descending") < 0, true);
    assertEqual(compareRosterStaffData(alex, blair, "role", "ascending") < 0, true);
    assertEqual(compareRosterStaffData(alex, blair, "name", "ascending") < 0, true);
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
