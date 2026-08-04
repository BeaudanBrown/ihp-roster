import { isFrontendSurfaceMountConfig as isGeneratedFrontendSurfaceMountConfig, isLiveFragmentsRefreshEventDetail, isLiveUpdateMessage, isSurfaceFragmentKey } from "../generated/contracts";
import {
    frontendSurfaceInstanceId,
    frontendSurfaceMountMatchesOwnerSurface,
    parseFrontendSurfaceSubscriptionConfig,
    reconcileFrontendSurfaceInstances,
    scanFrontendSurfaceMountInstances,
    type FrontendSurfaceMountedInstance,
} from "../live-updates/mount";
import { assertDeepEqual, assertEqual, test } from "./harness";

const validFragmentKey = { surface: "timesheets", kind: "timesheet-toolbar", params: null } as const;
const executableDescriptor = {
    fragmentKey: validFragmentKey,
    targetId: "timesheet-toolbar",
    url: "/TimesheetToolbar",
    deferUntilBlur: false,
    protectionPolicy: { kind: "none" },
};

const validScope = { surface: "timesheets", scope: { venueId: "venue-1", weekOffset: 0 } };

const exactTimesheetsMount = {
    surface: "timesheets",
    scopeKey: "timesheets:venue-1:3",
    mountKey: "primary",
    fragments: [
        {
            fragmentKey: { surface: "timesheets", kind: "timesheet-day-section", params: { dayOffset: 2 } },
            targetId: "timesheet-day-section-2",
            url: "/ShowTimesheetDaySectionFragment?weekOffset=3&dayOffset=2",
            protection: { kind: "replace" },
        },
    ],
    subscription: {
        scope: { surface: "timesheets", scope: { venueId: "venue-1", weekOffset: 3 } },
    },
};

test("generated FrontendSurface mount parser is exact and surface-discriminated", () => {
    assertEqual(isGeneratedFrontendSurfaceMountConfig(exactTimesheetsMount), true);
    assertEqual(isGeneratedFrontendSurfaceMountConfig({ ...exactTimesheetsMount, mountState: {} }), false);
    assertEqual(isGeneratedFrontendSurfaceMountConfig({ ...exactTimesheetsMount, fragments: [{ ...exactTimesheetsMount.fragments[0], loadPolicy: "eager" }] }), false);
    assertEqual(isGeneratedFrontendSurfaceMountConfig({ ...exactTimesheetsMount, subscription: { scope: { surface: "timesheets", scope: { venueId: "venue-1", weekOffset: "3" } } } }), false);
    assertEqual(isGeneratedFrontendSurfaceMountConfig({ ...exactTimesheetsMount, fragments: [{ ...exactTimesheetsMount.fragments[0], fragmentKey: { surface: "timesheets", kind: "timesheet-day-section", params: { dayOffset: "2" } } }] }), false);
    assertEqual(isGeneratedFrontendSurfaceMountConfig({ ...exactTimesheetsMount, fragments: [{ ...exactTimesheetsMount.fragments[0], fragmentKey: { surface: "roster", kind: "roster-content", params: {} } }] }), false);
    assertEqual(isGeneratedFrontendSurfaceMountConfig({ ...exactTimesheetsMount, fragments: [{ ...exactTimesheetsMount.fragments[0], protection: { kind: "focused-field" } }] }), false);
    assertEqual(isGeneratedFrontendSurfaceMountConfig({ ...exactTimesheetsMount, subscription: { scope: { surface: "roster", scope: { venueId: "venue-1", rosterGroupId: "group-1", weekOffset: 3 } } } }), false);
    assertEqual(isGeneratedFrontendSurfaceMountConfig({ ...exactTimesheetsMount, subscription: null }), false);
    if (!isGeneratedFrontendSurfaceMountConfig(exactTimesheetsMount)) throw new Error("expected exact Timesheets mount fixture");
    assertEqual(frontendSurfaceMountMatchesOwnerSurface(exactTimesheetsMount, "timesheets"), true);
    assertEqual(frontendSurfaceMountMatchesOwnerSurface(exactTimesheetsMount, "roster"), false);
    assertEqual(frontendSurfaceMountMatchesOwnerSurface(exactTimesheetsMount, null), false);
});

type LocalFragmentFixture = {
    kind: string;
    params: unknown;
    targetId: string;
    url: string;
    protection: unknown;
};

type SurfaceMountFixture = {
    surface: string;
    scopeKey: string;
    mountKey: string;
    fragments: LocalFragmentFixture[];
};

function exactMountConfig(config: SurfaceMountFixture) {
    return {
        surface: config.surface,
        scopeKey: config.scopeKey,
        mountKey: config.mountKey,
        fragments: config.fragments.map((fragment) => ({
            fragmentKey: {
                surface: config.surface,
                kind: fragment.kind,
                params: fragment.params,
            },
            targetId: fragment.targetId,
            url: fragment.url,
            protection: fragment.protection,
        })),
        subscription: null,
    };
}

function withSurfaceSubscription(config: SurfaceMountFixture, scopeFields: unknown) {
    return {
        ...exactMountConfig(config),
        subscription: {
            scope: { surface: config.surface, scope: scopeFields },
        },
    };
}

test("FrontendSurface config parser derives Timesheets live subscriptions from mounted fragments", () => {
    const config = parseFrontendSurfaceSubscriptionConfig(withSurfaceSubscription({
        surface: "timesheets",
        scopeKey: "timesheets:venue-1:3",
        mountKey: "primary",
        fragments: [{
            kind: "timesheet-day-section",
            params: { dayOffset: 2 },
            targetId: "timesheet-day-section-2",
            url: "/ShowTimesheetDaySectionFragment?weekOffset=3&dayOffset=2",
            protection: { kind: "replace" },
        }],
    }, { venueId: "venue-1", weekOffset: 3 }));

    assertDeepEqual(config?.scope, { surface: "timesheets", scope: { venueId: "venue-1", weekOffset: 3 } });
    assertEqual(config?.scopeKey, "timesheets:venue-1:3");
    assertEqual(config?.resyncFragments[0]?.targetId, "timesheet-day-section-2");
    assertDeepEqual(config?.resyncFragments[0]?.fragmentKey, { surface: "timesheets", kind: "timesheet-day-section", params: { dayOffset: 2 } });
});

test("FrontendSurface config parser derives Roster live subscriptions from mounted fragments", () => {
    const config = parseFrontendSurfaceSubscriptionConfig(withSurfaceSubscription({
        surface: "roster",
        scopeKey: "roster:venue-1:group-1:-1",
        mountKey: "primary",
        fragments: [
            {
                kind: "roster-content",
                params: null,
                targetId: "roster-content",
                url: "/ShowRosterWeekContentFragment?weekOffset=-1&rosterGroupId=group-1",
                protection: { kind: "replace" },
            },
            {
                kind: "roster-row",
                params: { rosterDayId: "day-1", rowIndex: 3 },
                targetId: "roster-row-day-1-3",
                url: "/ShowRosterWeekRowFragment?weekOffset=-1&rosterGroupId=group-1&rosterDayId=day-1&rowIndex=3",
                protection: { kind: "replace" },
            },
        ],
    }, { venueId: "venue-1", rosterGroupId: "group-1", weekOffset: -1 }));

    assertDeepEqual(config?.scope, { surface: "roster", scope: { venueId: "venue-1", rosterGroupId: "group-1", weekOffset: -1 } });
    assertEqual(config?.scopeKey, "roster:venue-1:group-1:-1");
    assertDeepEqual(config?.resyncFragments[0]?.fragmentKey, { surface: "roster", kind: "roster-content", params: null });
    assertDeepEqual(config?.resyncFragments[1]?.fragmentKey, { surface: "roster", kind: "roster-row", params: { rosterDayId: "day-1", rowIndex: 3 } });
});

test("FrontendSurface config parser derives Leave Requests live subscriptions from mounted fragments", () => {
    const config = parseFrontendSurfaceSubscriptionConfig(withSurfaceSubscription({
        surface: "leave-requests",
        scopeKey: "leave-requests:venue-1",
        mountKey: "primary",
        fragments: [
            {
                kind: "leave-section-count",
                params: { leaveSection: "pending" },
                targetId: "leave-pending-count",
                url: "/ShowLeaveRequestsContentFragment?fragment=leave-section-count&section=pending",
                protection: { kind: "replace" },
            },
            {
                kind: "leave-section-list",
                params: { leaveSection: "pending" },
                targetId: "leave-pending-list",
                url: "/ShowLeaveRequestsContentFragment?fragment=leave-section-list&section=pending",
                protection: { kind: "replace" },
            },
        ],
    }, { venueId: "venue-1" }));

    assertDeepEqual(config?.scope, { surface: "leave-requests", scope: { venueId: "venue-1" } });
    assertEqual(config?.scopeKey, "leave-requests:venue-1");
    assertDeepEqual(config?.resyncFragments[0]?.fragmentKey, { surface: "leave-requests", kind: "leave-section-count", params: { leaveSection: "pending" } });
    assertDeepEqual(config?.resyncFragments[1]?.fragmentKey, { surface: "leave-requests", kind: "leave-section-list", params: { leaveSection: "pending" } });
});

test("FrontendSurface config parser derives Billing and Support live subscriptions from mounted fragments", () => {
    const billing = parseFrontendSurfaceSubscriptionConfig(withSurfaceSubscription({
        surface: "billing",
        scopeKey: "billing:venue-1",
        mountKey: "primary",
        fragments: [{
            kind: "billing-status",
            params: null,
            targetId: "billing-status-fragment",
            url: "/ShowBillingStatusFragment",
            protection: { kind: "replace" },
        }],
    }, { venueId: "venue-1" }));

    assertDeepEqual(billing?.scope, { surface: "billing", scope: { venueId: "venue-1" } });
    assertDeepEqual(billing?.resyncFragments[0]?.fragmentKey, { surface: "billing", kind: "billing-status", params: null });

    const support = parseFrontendSurfaceSubscriptionConfig(withSurfaceSubscription({
        surface: "support",
        scopeKey: "support",
        mountKey: "primary",
        fragments: [{
            kind: "support-public-holidays",
            params: null,
            targetId: "support-public-holidays",
            url: "/ShowPublicHolidaysSection",
            protection: { kind: "replace" },
        }],
    }, {}));

    assertDeepEqual(support?.scope, { surface: "support", scope: {} });
    assertDeepEqual(support?.resyncFragments[0]?.fragmentKey, { surface: "support", kind: "support-public-holidays", params: null });
});

test("FrontendSurface config parser derives Profile live subscriptions from mounted fragments", () => {
    const config = parseFrontendSurfaceSubscriptionConfig(withSurfaceSubscription({
        surface: "profile",
        scopeKey: "profile:venue-1:staff-1",
        mountKey: "primary",
        fragments: [{
            kind: "profile-details-section",
            params: null,
            targetId: "profile-details",
            url: "/ShowProfileContentFragment?section=profile",
            protection: { kind: "replace" },
        }],
    }, { venueId: "venue-1", staffId: "staff-1" }));

    assertDeepEqual(config?.scope, { surface: "profile", scope: { venueId: "venue-1", staffId: "staff-1" } });
    assertEqual(config?.scopeKey, "profile:venue-1:staff-1");
    assertDeepEqual(config?.resyncFragments[0]?.fragmentKey, { surface: "profile", kind: "profile-details-section", params: null });
});

test("FrontendSurface config parser treats Admin page composition mount as non-subscribing", () => {
    const config = parseFrontendSurfaceSubscriptionConfig(exactMountConfig({
        surface: "admin-page",
        scopeKey: "admin-page:venue-1",
        mountKey: "primary",
        fragments: [{
            kind: "admin-page-content",
            params: null,
            targetId: "admin-page-content-fragment",
            url: "/Admin",
            protection: { kind: "replace" },
        }],
    }));

    assertEqual(config, null);

    const xeroConfig = parseFrontendSurfaceSubscriptionConfig(exactMountConfig({
        surface: "admin-xero-page",
        scopeKey: "admin-xero-page:venue-1",
        mountKey: "primary",
        fragments: [{
            kind: "admin-xero-page-content",
            params: null,
            targetId: "admin-xero-page-content-fragment",
            url: "/Xero",
            protection: { kind: "replace" },
        }],
    }));
    assertEqual(xeroConfig, null);
});

test("FrontendSurface config parser preserves reusable focused-field protection", () => {
    const config = parseFrontendSurfaceSubscriptionConfig(withSurfaceSubscription({
        surface: "profile",
        scopeKey: "profile:venue-1:staff-1",
        mountKey: "primary",
        fragments: [{
            kind: "profile-details-section",
            params: null,
            targetId: "profile-details",
            url: "/ShowProfileContentFragment?section=profile",
            protection: {
                kind: "focused-field",
                activeSelector: "input[data-profile-field]:focus",
                fieldKeyAttr: "data-profile-field",
                fieldNameFallback: true,
                containerSelector: "form",
            },
        }],
    }, { venueId: "venue-1", staffId: "staff-1" }));

    assertDeepEqual(config?.resyncFragments[0]?.protection, {
        kind: "focused-field",
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
    const parent: FrontendSurfaceMountedInstance = { instanceId: "parent:scope:primary", surface: "parent", scopeKey: "parent:scope", mountKey: "primary", depth: 0 };
    const child: FrontendSurfaceMountedInstance = { instanceId: "child:scope:primary", surface: "child", scopeKey: "child:scope", mountKey: "primary", depth: 1 };
    const grandchild: FrontendSurfaceMountedInstance = { instanceId: "grandchild:scope:primary", surface: "grandchild", scopeKey: "grandchild:scope", mountKey: "primary", depth: 2 };
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
    const parent: FrontendSurfaceMountedInstance = { instanceId: "parent:scope:primary", surface: "parent", scopeKey: "parent:scope", mountKey: "primary", depth: 0 };
    const oldChild: FrontendSurfaceMountedInstance = { instanceId: "child:old:primary", surface: "child", scopeKey: "child:old", mountKey: "primary", depth: 1 };
    const newChild: FrontendSurfaceMountedInstance = { instanceId: "child:new:primary", surface: "child", scopeKey: "child:new", mountKey: "primary", depth: 1 };
    const active = new Map([
        [parent.instanceId, parent],
        [oldChild.instanceId, oldChild],
    ]);

    const reconciliation = reconcileFrontendSurfaceInstances(active, [parent, newChild]);

    assertDeepEqual(reconciliation.retained.map((instance) => instance.instanceId), [parent.instanceId]);
    assertDeepEqual(reconciliation.removed.map((instance) => instance.instanceId), [oldChild.instanceId]);
    assertDeepEqual(reconciliation.added.map((instance) => instance.instanceId), [newChild.instanceId]);
});

test("generated live protocol accepts semantic keys and rejects executable descriptors", () => {
    assertEqual(isSurfaceFragmentKey(validFragmentKey), true);
    assertEqual(isSurfaceFragmentKey({ kind: "timesheet_day_section" }), false);
    assertEqual(isSurfaceFragmentKey(executableDescriptor), false);
});

test("generated actor refresh parser is exact and uses per-surface scope and fragment guards", () => {
    const detail = {
        scope: validScope,
        scopeKey: "timesheets:venue-1:0",
        fragments: [validFragmentKey],
    };
    assertEqual(isLiveFragmentsRefreshEventDetail(detail), true);
    assertEqual(isLiveFragmentsRefreshEventDetail({ ...detail, elt: {} }), false);
    assertEqual(isLiveFragmentsRefreshEventDetail({ ...detail, executableUrl: "/unsafe" }), false);
    assertEqual(isLiveFragmentsRefreshEventDetail({ ...detail, scope: { surface: "timesheets", scope: { venueId: "venue-1", weekOffset: "0" } } }), false);
    assertEqual(isLiveFragmentsRefreshEventDetail({ ...detail, fragments: [{ surface: "timesheets", kind: "timesheet-day-section", params: { dayOffset: "1" } }] }), false);
});

test("generated live update message guard checks websocket payload discriminants and primitives", () => {
    assertEqual(isLiveUpdateMessage({
        type: "subscribed",
        scope: validScope,
        scopeKey: "timesheets:venue-1:0",
        currentVersion: 1,
        resync: false,
    }), true);
    assertEqual(isLiveUpdateMessage({
        type: "invalidate",
        scope: validScope,
        scopeKey: "timesheets:venue-1:0",
        version: 2,
        fragments: [validFragmentKey],
        sourceClientId: null,
    }), true);
    assertEqual(isLiveUpdateMessage({ type: "unknown", message: "nope" }), false);
    assertEqual(isLiveUpdateMessage({ type: "subscribed", scope: validScope, scopeKey: "x", currentVersion: "1", resync: false }), false);
    assertEqual(isLiveUpdateMessage({ type: "invalidate", scope: validScope, scopeKey: "x", version: 1, fragments: [executableDescriptor], sourceClientId: null }), false);
    assertEqual(isLiveUpdateMessage({ type: "error", message: 500 }), false);
});
