import { parseLiveUpdateSurfaceConfig } from "../live-updates/validation";
import { assertDeepEqual, assertEqual, test } from "./harness";

test("live update surface validator accepts narrow declarative configs", () => {
    const config = parseLiveUpdateSurfaceConfig({
        feature: "timesheets",
        scope: { kind: "timesheet_week", venueId: "venue-1", weekOffset: 0 },
        scopeKey: "timesheet_week:venue-1:0",
        socketPath: "/custom-live",
        resyncFragments: [
            {
                fragmentKey: { kind: "timesheet_toolbar" },
                targetId: "timesheet-toolbar",
                url: "/TimesheetToolbar",
                deferUntilBlur: false,
            },
            { targetId: "missing-url" },
        ],
        decorateRequestsWithin: ["form", "", 42],
    });

    assertEqual(config?.feature, "timesheets");
    assertEqual(config?.scopeKey, "timesheet_week:venue-1:0");
    assertEqual(config?.socketPath, "/custom-live");
    assertEqual(config?.resyncFragments.length, 1);
    assertDeepEqual(config?.decorateRequestsWithin, ["form"]);
});

test("live update surface validator rejects missing scope and scope key", () => {
    assertEqual(parseLiveUpdateSurfaceConfig(null), null);
    assertEqual(parseLiveUpdateSurfaceConfig({ scopeKey: "missing-scope" }), null);
    assertEqual(parseLiveUpdateSurfaceConfig({ scope: { kind: "timesheet_week" }, scopeKey: "" }), null);
});
