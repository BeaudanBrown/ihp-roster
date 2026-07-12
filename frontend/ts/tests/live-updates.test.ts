import { surfaceFragmentKeyIdentity, surfaceFragmentKeysEqual, type FrontendSurfaceMountedFragmentConfig, type SurfaceScope } from "../generated/contracts";
import {
    buildLiveUpdateSubscribeCommand,
    buildSurfaceSubscription,
    buildLiveUpdateUnsubscribeCommand,
    liveUpdateFragmentMergeKey,
    liveUpdateInvalidationIsOwnEcho,
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
        weekOffset: 0,
    },
};

const fragment: FrontendSurfaceMountedFragmentConfig = {
    fragmentKey: { surface: "timesheets", kind: "timesheet-day-section", params: { dayOffset: 1 } },
    targetId: "timesheet-day-1",
    url: "/ShowTimesheetDay?dayOffset=1",
    protection: {
        kind: "focused-field",
        activeSelector: "input:focus",
        fieldKeyAttr: "data-live-field-key",
        fieldNameFallback: true,
        containerSelector: "[data-timesheet-entry]",
    },
};

test("live update command builder preserves backend-owned surface subscription contract", () => {
    const subscription = buildSurfaceSubscription(scope, "timesheets:v:0", [fragment.fragmentKey]);
    assertDeepEqual(subscription, {
        scope,
        scopeKey: "timesheets:v:0",
        fragments: [fragment.fragmentKey],
    });
    assertDeepEqual(buildLiveUpdateSubscribeCommand(subscription, "client-1", null), {
        type: "subscribe",
        subscription,
        clientId: "client-1",
        lastSeenVersion: null,
    });
    assertDeepEqual(buildLiveUpdateSubscribeCommand(subscription, "client-1", 4), {
        type: "subscribe",
        subscription,
        clientId: "client-1",
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
        '["timesheets","timesheet-day-section",{"dayOffset":1}]:timesheet-day-1'
    );
    assertEqual(liveUpdateFragmentMergeKey({ ...fragment, targetId: "" }), null);
});

test("live update invalidations request resync on version gaps and empty payloads", () => {
    assertEqual(liveUpdateInvalidationShouldResync(2, 4, 1), "gap");
    assertEqual(liveUpdateInvalidationShouldResync(2, 3, 0), "empty");
    assertEqual(liveUpdateInvalidationShouldResync(null, 10, 1), null);
    assertEqual(liveUpdateInvalidationShouldResync(3, 3, 1), null);
});

test("live update invalidations suppress same-client websocket echoes only", () => {
    assertEqual(liveUpdateInvalidationIsOwnEcho("client-1", "client-1"), true);
    assertEqual(liveUpdateInvalidationIsOwnEcho("client-2", "client-1"), false);
    assertEqual(liveUpdateInvalidationIsOwnEcho(null, "client-1"), false);
    assertEqual(liveUpdateInvalidationIsOwnEcho("client-1", null), false);
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
        params: { dayOffset: 1 },
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
