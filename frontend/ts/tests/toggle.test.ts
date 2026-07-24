import {
    parseToggleConfiguration,
    toggleTargetForChecked,
    toggleTransportState,
} from "../app-toggle-buttons";
import { assertDeepEqual, assertThrows, test } from "./harness";

const allGroupConfig = {
    presentationState: "unchecked",
    checkedTarget: { tag: "value", value: "all" },
    uncheckedTarget: { tag: "value", value: "group" },
    transportKey: "toggle-transport:staff-scope",
    submissionPolicy: "immediate",
    breakRegionKey: null,
} as const;

test("toggle configuration preserves explicit non-Boolean and inverted mappings", () => {
    const parsed = parseToggleConfiguration(JSON.stringify(allGroupConfig));
    assertDeepEqual(toggleTargetForChecked(parsed, true), { tag: "value", value: "all" });
    assertDeepEqual(toggleTargetForChecked(parsed, false), { tag: "value", value: "group" });

    const hideApproved = parseToggleConfiguration(JSON.stringify({
        ...allGroupConfig,
        checkedTarget: { tag: "value", value: "false" },
        uncheckedTarget: { tag: "value", value: "true" },
    }));
    assertDeepEqual(toggleTransportState(toggleTargetForChecked(hideApproved, true)), { value: "false", disabled: false });
    assertDeepEqual(toggleTransportState(toggleTargetForChecked(hideApproved, false)), { value: "true", disabled: false });
});

test("toggle configuration models unchecked repeated fields as explicit omission", () => {
    const parsed = parseToggleConfiguration(JSON.stringify({
        ...allGroupConfig,
        checkedTarget: { tag: "value", value: "monday" },
        uncheckedTarget: { tag: "omitted" },
        submissionPolicy: "deferred",
    }));
    assertDeepEqual(toggleTransportState(toggleTargetForChecked(parsed, false)), { value: "", disabled: true });
});

test("toggle configuration rejects malformed, extra, and contradictory state", () => {
    assertThrows(
        () => parseToggleConfiguration(JSON.stringify({ ...allGroupConfig, extra: true })),
        "Invalid ToggleConfig",
    );
    assertThrows(
        () => parseToggleConfiguration(JSON.stringify({ ...allGroupConfig, presentationState: "enabled" })),
        "Invalid ToggleConfig",
    );
    assertThrows(
        () => parseToggleConfiguration(JSON.stringify({ ...allGroupConfig, uncheckedTarget: allGroupConfig.checkedTarget })),
        "checkedTarget and uncheckedTarget must differ",
    );
});
