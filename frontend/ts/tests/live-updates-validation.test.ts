import { encodeLiveSurfaceConfig, isLiveUpdateMessage, isLiveUpdateWireFragment, parseLiveSurfaceConfig } from "../generated/contracts";
import {
    frontendSurfaceInstanceId,
    parseFrontendSurfaceSubscriptionConfig,
    reconcileFrontendSurfaceInstances,
    scanFrontendSurfaceMountInstances,
    type FrontendSurfaceMountedInstance,
} from "../live-updates/frontend-surface";
import { parseLiveUpdateSurfaceConfig } from "../live-updates/validation";
import { assertDeepEqual, assertEqual, assertThrows, test } from "./harness";

const validFragment = {
    fragmentKey: { kind: "timesheet_toolbar" },
    targetId: "timesheet-toolbar",
    url: "/TimesheetToolbar",
    deferUntilBlur: false,
    protectionPolicy: { kind: "none" },
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

test("generated parse helpers reject unknown input and encode helpers preserve JSON-shaped DTOs", () => {
    const config = parseLiveSurfaceConfig(validSurfaceConfig);

    assertDeepEqual(encodeLiveSurfaceConfig(config), validSurfaceConfig);
    assertThrows(
        () => parseLiveSurfaceConfig({ ...validSurfaceConfig, scope: { kind: "unknown_scope" } }),
        "Invalid LiveSurfaceConfig",
    );
});

test("FrontendSurface config parser derives Timesheets live subscriptions from mounted fragments", () => {
    const config = parseFrontendSurfaceSubscriptionConfig({
        surface: "timesheets",
        scopeKey: "timesheets:venue-1:3",
        mountKey: "primary",
        mountState: { showApproved: false, showAllStaff: true, staffFilterId: null },
        fragments: [
            {
                key: { kind: "timesheet-day-section", params: { dayOffset: 2 } },
                targetId: "timesheet-day-section-2",
                url: "/ShowTimesheetDaySectionFragment?weekOffset=3&dayOffset=2&showApproved=false&showAllStaff=true",
                protection: { kind: "replace" },
                loadPolicy: "eager",
            },
        ],
    });

    assertEqual(config?.feature, "timesheets");
    assertDeepEqual(config?.scope, { kind: "timesheet_week", venueId: "venue-1", weekOffset: 3 });
    assertEqual(config?.scopeKey, "timesheet_week:venue-1:3");
    assertEqual(config?.resyncFragments[0]?.targetId, "timesheet-day-section-2");
    assertDeepEqual(config?.resyncFragments[0]?.fragmentKey, { kind: "timesheet_day_section", dayOffset: 2 });
});

test("FrontendSurface config parser derives Roster live subscriptions from mounted fragments", () => {
    const config = parseFrontendSurfaceSubscriptionConfig({
        surface: "roster",
        scopeKey: "roster:venue-1:group-1:-1",
        mountKey: "primary",
        mountState: {},
        fragments: [
            {
                key: { kind: "roster-content", params: null },
                targetId: "roster-content",
                url: "/ShowRosterWeekContentFragment?weekOffset=-1&rosterGroupId=group-1",
                protection: { kind: "replace" },
                loadPolicy: "eager",
            },
            {
                key: { kind: "roster-row", params: { rosterDayId: "day-1", rowIndex: 3 } },
                targetId: "roster-row-day-1-3",
                url: "/ShowRosterWeekRowFragment?weekOffset=-1&rosterGroupId=group-1&rosterDayId=day-1&rowIndex=3",
                protection: { kind: "replace" },
                loadPolicy: "lazy",
            },
        ],
    });

    assertEqual(config?.feature, "roster");
    assertDeepEqual(config?.scope, { kind: "roster_week", venueId: "venue-1", rosterGroupId: "group-1", weekOffset: -1 });
    assertEqual(config?.scopeKey, "roster_week:venue-1:group-1:-1");
    assertDeepEqual(config?.resyncFragments[0]?.fragmentKey, { kind: "roster_content" });
    assertDeepEqual(config?.resyncFragments[1]?.fragmentKey, { kind: "roster_row", rosterDayId: "day-1", rowIndex: 3 });
});

test("FrontendSurface config parser derives Leave Requests live subscriptions from mounted fragments", () => {
    const config = parseFrontendSurfaceSubscriptionConfig({
        surface: "leave-requests",
        scopeKey: "leave-requests:venue-1",
        mountKey: "primary",
        mountState: null,
        fragments: [
            {
                key: { kind: "leave-requests-content", params: null },
                targetId: "leave-requests-content",
                url: "/ShowLeaveRequestsContentFragment",
                protection: { kind: "replace" },
                loadPolicy: "eager",
            },
        ],
    });

    assertEqual(config?.feature, "leave-requests");
    assertDeepEqual(config?.scope, { kind: "leave_requests", venueId: "venue-1" });
    assertEqual(config?.scopeKey, "leave_requests:venue-1");
    assertDeepEqual(config?.resyncFragments[0]?.fragmentKey, { kind: "leave_requests_content" });
});

test("FrontendSurface config parser derives Billing and Support live subscriptions from mounted fragments", () => {
    const billing = parseFrontendSurfaceSubscriptionConfig({
        surface: "billing",
        scopeKey: "billing:venue-1",
        mountKey: "primary",
        mountState: null,
        fragments: [
            {
                key: { kind: "billing-status", params: null },
                targetId: "billing-status-fragment",
                url: "/ShowBillingStatusFragment",
                protection: { kind: "replace" },
                loadPolicy: "eager",
            },
        ],
    });

    assertDeepEqual(billing?.scope, { kind: "billing", venueId: "venue-1" });
    assertDeepEqual(billing?.resyncFragments[0]?.fragmentKey, { kind: "billing_status" });

    const support = parseFrontendSurfaceSubscriptionConfig({
        surface: "support",
        scopeKey: "support",
        mountKey: "primary",
        mountState: null,
        fragments: [
            {
                key: { kind: "support-public-holidays", params: null },
                targetId: "support-public-holidays-section",
                url: "/ShowPublicHolidaysSection",
                protection: { kind: "replace" },
                loadPolicy: "eager",
            },
        ],
    });

    assertDeepEqual(support?.scope, { kind: "support_platform" });
    assertDeepEqual(support?.resyncFragments[0]?.fragmentKey, { kind: "support_public_holidays_section" });
});

test("FrontendSurface config parser derives Profile live subscriptions from mounted fragments", () => {
    const config = parseFrontendSurfaceSubscriptionConfig({
        surface: "profile",
        scopeKey: "profile:venue-1:staff-1",
        mountKey: "primary",
        mountState: null,
        fragments: [
            {
                key: { kind: "profile-details-section", params: null },
                targetId: "profile-details",
                url: "/ShowProfileContentFragment?section=profile",
                protection: { kind: "replace" },
                loadPolicy: "eager",
            },
        ],
    });

    assertEqual(config?.feature, "profile");
    assertDeepEqual(config?.scope, { kind: "profile", venueId: "venue-1", staffId: "staff-1" });
    assertEqual(config?.scopeKey, "profile:venue-1:staff-1");
    assertDeepEqual(config?.resyncFragments[0]?.fragmentKey, { kind: "profile_details_section" });
});

test("FrontendSurface config parser treats Admin page composition mount as non-subscribing", () => {
    const config = parseFrontendSurfaceSubscriptionConfig({
        surface: "admin-page",
        scopeKey: "admin-page:venue-1",
        mountKey: "primary",
        mountState: null,
        fragments: [
            {
                key: { kind: "admin-page-content", params: null },
                targetId: "admin-page-content-fragment",
                url: "/Admin",
                protection: { kind: "replace" },
                loadPolicy: "eager",
            },
        ],
    });

    assertEqual(config, null);

    const xeroConfig = parseFrontendSurfaceSubscriptionConfig({
        surface: "admin-xero-page",
        scopeKey: "admin-xero-page:venue-1",
        mountKey: "primary",
        mountState: null,
        fragments: [
            {
                key: { kind: "admin-xero-page-content", params: null },
                targetId: "admin-xero-page-content-fragment",
                url: "/Xero",
                protection: { kind: "replace" },
                loadPolicy: "eager",
            },
        ],
    });
    assertEqual(xeroConfig, null);
});

test("FrontendSurface config parser preserves reusable focused-field protection", () => {
    const config = parseFrontendSurfaceSubscriptionConfig({
        surface: "profile",
        scopeKey: "profile:venue-1:staff-1",
        mountKey: "primary",
        mountState: null,
        fragments: [
            {
                key: { kind: "profile-details-section", params: null },
                targetId: "profile-details",
                url: "/ShowProfileContentFragment?section=profile",
                protection: {
                    kind: "focused-field",
                    activeSelector: "input[data-profile-field]:focus",
                    fieldKeyAttr: "data-profile-field",
                    fieldNameFallback: true,
                    containerSelector: "form",
                },
                loadPolicy: "eager",
            },
        ],
    });

    assertDeepEqual(config?.resyncFragments[0]?.protectionPolicy, {
        kind: "focused_field",
        activeSelector: "input[data-profile-field]:focus",
        fieldKeyAttr: "data-profile-field",
        fieldNameFallback: true,
        containerSelector: "form",
    });
});

test("FrontendSurface mount scanner is safe without a browser document", () => {
    assertDeepEqual(scanFrontendSurfaceMountInstances().map((instance) => instance.instanceId), []);
    assertEqual(frontendSurfaceInstanceId({ surface: "child", scopeKey: "child:venue-1", mountKey: "main" }), "child:child:venue-1:main");
});

test("FrontendSurface instance reconciliation disposes removed children deepest first", () => {
    const parentEl = {} as HTMLElement;
    const childEl = {} as HTMLElement;
    const grandchildEl = {} as HTMLElement;
    const parent: FrontendSurfaceMountedInstance = { instanceId: "parent:scope:primary", surface: "parent", scopeKey: "parent:scope", mountKey: "primary", ownerEl: parentEl, depth: 0 };
    const child: FrontendSurfaceMountedInstance = { instanceId: "child:scope:primary", surface: "child", scopeKey: "child:scope", mountKey: "primary", ownerEl: childEl, depth: 1 };
    const grandchild: FrontendSurfaceMountedInstance = { instanceId: "grandchild:scope:primary", surface: "grandchild", scopeKey: "grandchild:scope", mountKey: "primary", ownerEl: grandchildEl, depth: 2 };
    const active = new Map([
        [parent.instanceId, parent],
        [child.instanceId, child],
        [grandchild.instanceId, grandchild],
    ]);

    const reconciliation = reconcileFrontendSurfaceInstances(active, [parent]);

    assertDeepEqual(reconciliation.added.map((instance) => instance.instanceId), []);
    assertDeepEqual(reconciliation.retained.map((instance) => instance.instanceId), [parent.instanceId]);
    assertDeepEqual(reconciliation.removed.map((instance) => instance.instanceId), [grandchild.instanceId, child.instanceId]);
});

test("FrontendSurface instance reconciliation handles same, removed, and newly scoped children", () => {
    const parentEl = {} as HTMLElement;
    const oldChildEl = {} as HTMLElement;
    const newChildEl = {} as HTMLElement;
    const parent: FrontendSurfaceMountedInstance = { instanceId: "parent:scope:primary", surface: "parent", scopeKey: "parent:scope", mountKey: "primary", ownerEl: parentEl, depth: 0 };
    const oldChild: FrontendSurfaceMountedInstance = { instanceId: "child:old:primary", surface: "child", scopeKey: "child:old", mountKey: "primary", ownerEl: oldChildEl, depth: 1 };
    const newChild: FrontendSurfaceMountedInstance = { instanceId: "child:new:primary", surface: "child", scopeKey: "child:new", mountKey: "primary", ownerEl: newChildEl, depth: 1 };
    const active = new Map([
        [parent.instanceId, parent],
        [oldChild.instanceId, oldChild],
    ]);

    const reconciliation = reconcileFrontendSurfaceInstances(active, [parent, newChild]);

    assertDeepEqual(reconciliation.retained.map((instance) => instance.instanceId), [parent.instanceId]);
    assertDeepEqual(reconciliation.removed.map((instance) => instance.instanceId), [oldChild.instanceId]);
    assertDeepEqual(reconciliation.added.map((instance) => instance.instanceId), [newChild.instanceId]);
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
