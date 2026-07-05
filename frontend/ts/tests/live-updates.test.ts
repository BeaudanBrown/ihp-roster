import type { SurfaceScope, SurfaceWireFragment } from "../generated/contracts";
import {
    buildLiveUpdateSubscribeCommand,
    buildSurfaceSubscription,
    buildLiveUpdateUnsubscribeCommand,
    liveUpdateFragmentMergeKey,
    liveUpdateInvalidationShouldResync,
    liveUpdateMessageScopeKey,
    normalizeLiveUpdateVersion,
} from "../live-updates/protocol";
import { assertDeepEqual, assertEqual, test } from "./harness";

const scope: SurfaceScope = {
    surface: "timesheets",
    scope: {
        venueId: "00000000-0000-0000-0000-000000000001",
        weekOffset: 0,
    },
};

const fragment: SurfaceWireFragment = {
    fragmentKey: { surface: "timesheets", kind: "timesheet-day-section", params: { dayOffset: 1 } },
    targetId: "timesheet-day-1",
    url: "/ShowTimesheetDay?dayOffset=1",
    deferUntilBlur: true,
    protectionPolicy: {
        kind: "focused-field",
        activeSelector: "input:focus",
        fieldKeyAttr: "data-live-field-key",
        fieldNameFallback: true,
        containerSelector: "[data-timesheet-entry]",
    },
};

test("live update command builder preserves backend-owned surface subscription contract", () => {
    const subscription = buildSurfaceSubscription(scope, "timesheets:v:0", [fragment]);
    assertDeepEqual(subscription, {
        scope,
        scopeKey: "timesheets:v:0",
        mountedFragments: [fragment],
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

test("live update message helpers normalize scope keys and versions", () => {
    assertEqual(liveUpdateMessageScopeKey({ scopeKey: "timesheets:v:0" }), "timesheets:v:0");
    assertEqual(liveUpdateMessageScopeKey({ scopeKey: "" }), null);
    assertEqual(normalizeLiveUpdateVersion(0), 0);
    assertEqual(normalizeLiveUpdateVersion(12), 12);
    assertEqual(normalizeLiveUpdateVersion(-1), null);
    assertEqual(normalizeLiveUpdateVersion(1.5), null);
});

test("live update fragment merge key includes structural fragment key and target", () => {
    assertEqual(
        liveUpdateFragmentMergeKey(fragment),
        '{"surface":"timesheets","kind":"timesheet-day-section","params":{"dayOffset":1}}:timesheet-day-1'
    );
    assertEqual(liveUpdateFragmentMergeKey({ ...fragment, targetId: "" }), null);
});

test("live update invalidations request resync on version gaps and empty payloads", () => {
    assertEqual(liveUpdateInvalidationShouldResync(2, 4, 1), "gap");
    assertEqual(liveUpdateInvalidationShouldResync(2, 3, 0), "empty");
    assertEqual(liveUpdateInvalidationShouldResync(null, 10, 1), null);
    assertEqual(liveUpdateInvalidationShouldResync(3, 3, 1), null);
});
