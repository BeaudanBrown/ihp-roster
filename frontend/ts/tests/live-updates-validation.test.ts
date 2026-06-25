import { isLiveUpdateMessage, isLiveUpdateWireFragment } from "../generated/contracts";
import { parseLiveUpdateSurfaceConfig } from "../live-updates/validation";
import { assertDeepEqual, assertEqual, test } from "./harness";

const validFragment = {
    fragmentKey: { kind: "timesheet_toolbar" },
    targetId: "timesheet-toolbar",
    url: "/TimesheetToolbar",
    deferUntilBlur: false,
    protectionPolicy: null,
};

const validScope = { kind: "timesheet_week", venueId: "venue-1", weekOffset: 0 };

const validSurfaceConfig = {
    feature: "timesheets",
    scope: validScope,
    scopeKey: "timesheet_week:venue-1:0",
    socketPath: "/custom-live",
    resyncFragments: [validFragment],
    decorateRequestsWithin: ["form"],
};

test("generated live update surface validator accepts backend-owned declarative configs", () => {
    const config = parseLiveUpdateSurfaceConfig(validSurfaceConfig);

    assertEqual(config?.feature, "timesheets");
    assertEqual(config?.scopeKey, "timesheet_week:venue-1:0");
    assertEqual(config?.socketPath, "/custom-live");
    assertEqual(config?.resyncFragments.length, 1);
    assertDeepEqual(config?.decorateRequestsWithin, ["form"]);
});

test("generated live update surface validator rejects malformed boundary JSON", () => {
    assertEqual(parseLiveUpdateSurfaceConfig(null), null);
    assertEqual(parseLiveUpdateSurfaceConfig({ ...validSurfaceConfig, scope: { kind: "unknown_scope" } }), null);
    assertEqual(parseLiveUpdateSurfaceConfig({ ...validSurfaceConfig, scopeKey: 42 }), null);
    assertEqual(parseLiveUpdateSurfaceConfig({ ...validSurfaceConfig, socketPath: null }), null);
    assertEqual(parseLiveUpdateSurfaceConfig({ ...validSurfaceConfig, resyncFragments: [{ ...validFragment, url: 42 }] }), null);
    assertEqual(parseLiveUpdateSurfaceConfig({ ...validSurfaceConfig, decorateRequestsWithin: ["form", 42] }), null);
});

test("generated live update wire fragment guard rejects malformed fragment keys and fields", () => {
    assertEqual(isLiveUpdateWireFragment(validFragment), true);
    assertEqual(isLiveUpdateWireFragment({ ...validFragment, fragmentKey: { kind: "timesheet_day_section" } }), false);
    assertEqual(isLiveUpdateWireFragment({ ...validFragment, deferUntilBlur: "false" }), false);
    assertEqual(isLiveUpdateWireFragment({ ...validFragment, protectionPolicy: undefined }), false);
});

test("generated live update message guard checks websocket payload discriminants and primitives", () => {
    assertEqual(isLiveUpdateMessage({
        type: "subscribed",
        scope: validScope,
        scopeKey: "timesheet_week:venue-1:0",
        currentVersion: 1,
        resync: false,
    }), true);
    assertEqual(isLiveUpdateMessage({
        type: "invalidate",
        scope: validScope,
        scopeKey: "timesheet_week:venue-1:0",
        version: 2,
        fragments: [validFragment],
        sourceClientId: null,
    }), true);
    assertEqual(isLiveUpdateMessage({ type: "unknown", message: "nope" }), false);
    assertEqual(isLiveUpdateMessage({ type: "subscribed", scope: validScope, scopeKey: "x", currentVersion: "1", resync: false }), false);
    assertEqual(isLiveUpdateMessage({ type: "invalidate", scope: validScope, scopeKey: "x", version: 1, fragments: [{ ...validFragment, targetId: 7 }], sourceClientId: null }), false);
    assertEqual(isLiveUpdateMessage({ type: "error", message: 500 }), false);
});
