import { surfaceFragmentKeyIdentity, surfaceFragmentKeysEqual, type FrontendSurfaceMountedFragmentConfig, type SurfaceScope } from "../generated/contracts";
import { createLiveUpdateConnection } from "../live-updates/connection";
import { createLiveUpdateInvalidationRuntime, type LiveUpdateVersionStore } from "../live-updates/invalidation";
import type { LiveFragmentRefresher } from "../live-updates/refresh";
import type { SurfaceSubscription } from "../live-updates/runtime-types";
import {
    buildLiveUpdateSubscribeCommand,
    buildSurfaceSubscription,
    buildLiveUpdateUnsubscribeCommand,
    liveUpdateFragmentMergeKey,
    liveUpdateInvalidationShouldResync,
    liveUpdateMessageScopeKey,
    normalizeLiveUpdateVersion,
    resolveMountedFragmentsForInvalidation,
    serverPayloadFromHtmxTriggeredEvent,
} from "../live-updates/protocol";
import { assertDeepEqual, assertEqual, test } from "./harness";

const scope: SurfaceScope = {
    surface: "timesheets",
    scope: {
        venueId: "00000000-0000-0000-0000-000000000001",
        windowStartDate: "2025-01-06",
        windowEndDate: "2025-01-13",
        rosterCalendarRevision: 1,
    },
};

const fragment: FrontendSurfaceMountedFragmentConfig = {
    fragmentKey: { surface: "timesheets", kind: "timesheet-day-section", params: { operationalDate: "2025-01-07" } },
    targetId: "timesheet-day-2025-01-07",
    url: "/ShowTimesheetDaySectionFragment?operationalDate=2025-01-07",
    protection: {
        kind: "focused-field",
        activeSelector: "input:focus",
        fieldKeyAttr: "data-live-field-key",
        fieldNameFallback: true,
        containerSelector: "[data-timesheet-entry]",
    },
};

test("modular invalidation owner tolerates duplicate listener and actor refreshes", () => {
    const requested: FrontendSurfaceMountedFragmentConfig[] = [];
    let resyncCount = 0;
    const subscription: SurfaceSubscription = {
        scope,
        scopeKey: "timesheets:v:0",
        path: "/live-updates",
        resyncFragments: [fragment],
        renderedDependencyWatermark: 7,
        ownerEls: [],
        resync: () => { resyncCount += 1; },
    };
    const activeSubscriptions = new Map([[subscription.scopeKey, subscription]]);
    const refresher: LiveFragmentRefresher = {
        request: (candidate) => { requested.push(candidate); },
        flushInteractionDeferredFragmentsWithoutActiveSessions: () => undefined,
        flushFocusedFragmentsWithoutActiveInputs: () => undefined,
        stop: () => undefined,
    };
    const diagnostics = {
        beginPerfSpan: () => null,
        endPerfSpan: () => null,
        emitDebugEvent: () => undefined,
    };
    const runtime = createLiveUpdateInvalidationRuntime({
        activeSubscriptions,
        refresher,
        diagnostics,
    });

    runtime.handleMessage({
        type: "invalidate",
        scope,
        scopeKey: subscription.scopeKey,
        version: 1,
        fragments: [fragment.fragmentKey],
    });
    runtime.handleMessage({
        type: "invalidate",
        scope,
        scopeKey: subscription.scopeKey,
        version: 2,
        fragments: [fragment.fragmentKey],
    });
    runtime.handleActorEvent(new CustomEvent("actor-refresh", {
        detail: { scope, scopeKey: subscription.scopeKey, fragments: [fragment.fragmentKey] },
    }));

    assertDeepEqual(requested, [fragment, fragment, fragment]);
    assertEqual(resyncCount, 0);
});

test("Admin Xero reconnect refetches while unrelated global version gaps do not", () => {
    const xeroScope: SurfaceScope = {
        surface: "admin-xero",
        scope: { venueId: "00000000-0000-0000-0000-000000000001" },
    };
    const xeroFragment: FrontendSurfaceMountedFragmentConfig = {
        fragmentKey: { surface: "admin-xero", kind: "admin-xero-reference-sync", params: null },
        targetId: "admin-xero-reference-sync-fragment",
        url: "/ShowadminXeroReferenceSyncLiveFragment",
        protection: { kind: "replace" },
    };
    const requested: FrontendSurfaceMountedFragmentConfig[] = [];
    const refresher: LiveFragmentRefresher = {
        request: (candidate) => { requested.push(candidate); },
        flushInteractionDeferredFragmentsWithoutActiveSessions: () => undefined,
        flushFocusedFragmentsWithoutActiveInputs: () => undefined,
        stop: () => undefined,
    };
    const subscription: SurfaceSubscription = {
        scope: xeroScope,
        scopeKey: "admin-xero:00000000-0000-0000-0000-000000000001",
        path: "/live-updates",
        resyncFragments: [xeroFragment],
        renderedDependencyWatermark: 7,
        ownerEls: [],
        resync: (current) => current.resyncFragments.forEach(refresher.request),
    };
    const runtime = createLiveUpdateInvalidationRuntime({
        activeSubscriptions: new Map([[subscription.scopeKey, subscription]]),
        refresher,
        diagnostics: {
            beginPerfSpan: () => null,
            endPerfSpan: () => null,
            emitDebugEvent: () => undefined,
        },
    });

    runtime.handleMessage({
        type: "subscribed",
        scope: xeroScope,
        scopeKey: subscription.scopeKey,
        currentVersion: 1,
        resync: true,
    });
    runtime.handleMessage({
        type: "invalidate",
        scope: xeroScope,
        scopeKey: subscription.scopeKey,
        version: 3,
        fragments: [xeroFragment.fragmentKey],
    });

    assertDeepEqual(requested, [xeroFragment, xeroFragment]);
});

test("connection cleanup resets versions when the mounted subscription set becomes empty", () => {
    const subscription: SurfaceSubscription = {
        scope,
        scopeKey: "timesheets:v:0",
        path: "/live-updates",
        resyncFragments: [fragment],
        renderedDependencyWatermark: 7,
        ownerEls: [],
        resync: () => undefined,
    };
    const activeSubscriptions = new Map([[subscription.scopeKey, subscription]]);
    const cleared: string[] = [];
    const versions: LiveUpdateVersionStore = {
        get: () => 4,
        set: () => undefined,
        clear: (scopeKey) => { cleared.push(scopeKey); },
    };
    const targetWindow = {
        setTimeout,
        clearTimeout,
    } as unknown as Window & typeof globalThis;
    const connection = createLiveUpdateConnection({
        targetWindow,
        activeSubscriptions,
        versions,
        handleMessage: () => undefined,
        requestSync: () => undefined,
        diagnostics: {
            beginPerfSpan: () => null,
            endPerfSpan: () => null,
            emitDebugEvent: () => undefined,
        },
    });

    connection.sync(new Map());

    assertDeepEqual(cleared, [subscription.scopeKey]);
    assertEqual(activeSubscriptions.size, 0);
});

test("live update command builder preserves backend-owned surface subscription contract", () => {
    const subscription = buildSurfaceSubscription(scope, "timesheets:v:0", [fragment.fragmentKey], 7);
    assertDeepEqual(subscription, {
        scope,
        scopeKey: "timesheets:v:0",
        fragments: [fragment.fragmentKey],
        renderedDependencyWatermark: 7,
    });
    assertDeepEqual(buildLiveUpdateSubscribeCommand(subscription, null), {
        type: "subscribe",
        subscription,
        lastSeenVersion: null,
    });
    assertDeepEqual(buildLiveUpdateSubscribeCommand(subscription, 4), {
        type: "subscribe",
        subscription,
        lastSeenVersion: 4,
    });
    assertDeepEqual(buildLiveUpdateUnsubscribeCommand(subscription), {
        type: "unsubscribe",
        subscription,
    });
});

test("generated fragment-key identity is canonical across parameter property order", () => {
    const first = {
        surface: "roster",
        kind: "roster-row",
        params: { rosterDayId: "00000000-0000-0000-0000-000000000001", rowIndex: 3 },
    } as const;
    const reordered = {
        surface: "roster",
        kind: "roster-row",
        params: { rowIndex: 3, rosterDayId: "00000000-0000-0000-0000-000000000001" },
    } as const;
    const otherRow = { ...reordered, params: { ...reordered.params, rowIndex: 4 } } as const;

    assertEqual(surfaceFragmentKeyIdentity(first), surfaceFragmentKeyIdentity(reordered));
    assertEqual(surfaceFragmentKeysEqual(first, reordered), true);
    assertEqual(surfaceFragmentKeysEqual(first, otherRow), false);
});

test("live update message helpers normalize scope keys and versions", () => {
    assertEqual(liveUpdateMessageScopeKey({ scopeKey: "timesheets:v:0" }), "timesheets:v:0");
    assertEqual(liveUpdateMessageScopeKey({ scopeKey: "" }), null);
    assertEqual(normalizeLiveUpdateVersion(0), 0);
    assertEqual(normalizeLiveUpdateVersion(12), 12);
    assertEqual(normalizeLiveUpdateVersion(-1), null);
    assertEqual(normalizeLiveUpdateVersion(1.5), null);
});

test("HTMX actor event adaptation strips only its verified dispatch element", () => {
    const target = new EventTarget();
    const detail = { scopeKey: "timesheets:v:0", executableUrl: "/must-remain-for-exact-rejection", elt: target };

    assertDeepEqual(serverPayloadFromHtmxTriggeredEvent(detail, target), {
        scopeKey: "timesheets:v:0",
        executableUrl: "/must-remain-for-exact-rejection",
    });
    assertEqual(serverPayloadFromHtmxTriggeredEvent(detail, new EventTarget()), null);
    assertEqual(serverPayloadFromHtmxTriggeredEvent([], target), null);
});

test("live update fragment merge key includes structural fragment key and target", () => {
    assertEqual(
        liveUpdateFragmentMergeKey(fragment),
        '["timesheets","timesheet-day-section",{"operationalDate":"2025-01-07"}]:timesheet-day-2025-01-07'
    );
    assertEqual(liveUpdateFragmentMergeKey({ ...fragment, targetId: "" }), null);
});

test("live update invalidations request resync on version gaps and empty payloads", () => {
    assertEqual(liveUpdateInvalidationShouldResync(2, 4, 1), null);
    assertEqual(liveUpdateInvalidationShouldResync(2, 3, 0), "empty");
    assertEqual(liveUpdateInvalidationShouldResync(null, 10, 1), null);
    assertEqual(liveUpdateInvalidationShouldResync(3, 3, 1), null);
});

test("live update invalidations suppress same-client websocket echoes only", () => {
});

test("semantic invalidation keys resolve only through descriptors on local mounts", () => {
    const incomingKey = fragment.fragmentKey;
    const localDescriptor: FrontendSurfaceMountedFragmentConfig = {
        ...fragment,
        targetId: "local-target",
        url: "/authorized-local-fragment",
    };
    const reorderedIncomingKey = {
        kind: "timesheet-day-section",
        params: { operationalDate: "2025-01-07" },
        surface: "timesheets",
    } as const;
    const unknownKey = { surface: "roster", kind: "roster-content", params: {} } as const;

    assertDeepEqual(
        resolveMountedFragmentsForInvalidation(
            [{ scopeKey: "timesheets:v:0", resyncFragments: [localDescriptor] }],
            [incomingKey],
            "timesheets:v:0",
        ),
        [localDescriptor],
    );
    assertDeepEqual(
        resolveMountedFragmentsForInvalidation(
            [{ scopeKey: "timesheets:v:0", resyncFragments: [localDescriptor] }],
            [reorderedIncomingKey],
            "timesheets:v:0",
        ),
        [localDescriptor],
    );
    assertDeepEqual(
        resolveMountedFragmentsForInvalidation(
            [{ scopeKey: "timesheets:v:0", resyncFragments: [localDescriptor] }],
            [unknownKey],
            "timesheets:v:0",
        ),
        [],
    );
    assertDeepEqual(
        resolveMountedFragmentsForInvalidation([], [incomingKey], "timesheets:v:0"),
        [],
    );
    assertDeepEqual(
        resolveMountedFragmentsForInvalidation(
            [{ scopeKey: "timesheets:v:0", resyncFragments: [localDescriptor] }],
            [incomingKey],
            null,
        ),
        [],
    );
});

test("actor invalidation resolves every semantic key from one-shot subscription iterators", () => {
    const firstLocal: FrontendSurfaceMountedFragmentConfig = {
        ...fragment,
        targetId: "timesheet-day-local",
        url: "/local-day",
    };
    const secondLocal: FrontendSurfaceMountedFragmentConfig = {
        ...fragment,
        fragmentKey: { surface: "timesheets", kind: "timesheet-toolbar", params: {} },
        targetId: "timesheet-toolbar-local",
        url: "/local-toolbar",
    };
    const incomingFragments = [firstLocal.fragmentKey, secondLocal.fragmentKey];
    const subscriptions = new Map([
        ["timesheets:v:0", { scopeKey: "timesheets:v:0", resyncFragments: [firstLocal, secondLocal] }],
    ]).values();

    assertDeepEqual(
        resolveMountedFragmentsForInvalidation(subscriptions, incomingFragments, "timesheets:v:0"),
        [firstLocal, secondLocal],
    );
});

test("actor-local invalidation resolves through every duplicate mounted fragment in scope", () => {
    const actorFragmentKey = fragment.fragmentKey;
    const firstMount: FrontendSurfaceMountedFragmentConfig = {
        ...fragment,
        targetId: "timesheet-day-primary",
        url: "/primary-day",
    };
    const duplicateMount: FrontendSurfaceMountedFragmentConfig = {
        ...fragment,
        targetId: "timesheet-day-duplicate",
        url: "/duplicate-day",
    };
    const otherScopeMount: FrontendSurfaceMountedFragmentConfig = {
        ...fragment,
        targetId: "timesheet-day-other-week",
        url: "/other-week-day",
    };

    const resolved = resolveMountedFragmentsForInvalidation(
        [
            { scopeKey: "timesheets:v:0", resyncFragments: [firstMount, duplicateMount] },
            { scopeKey: "timesheets:v:1", resyncFragments: [otherScopeMount] },
        ],
        [actorFragmentKey],
        "timesheets:v:0",
    );

    assertDeepEqual(resolved, [firstMount, duplicateMount]);
});
