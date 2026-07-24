import {
    orderedRangeLabelForValue,
    orderedRangePositionPercent,
    orderedRangeStateForInput,
    parseOrderedRangeConfiguration,
    parseOrderedRangeStateConfiguration,
} from "../ordered-range/configuration";
import { assertDeepEqual, assertEqual, assertThrows, test } from "./harness";

const config = {
    minimumValue: 5,
    maximumValue: 9,
    stepValue: 1,
    defaultStartValue: 6,
    defaultEndValue: 8,
    valueLabels: ["5 AM", "6 AM", "7 AM", "8 AM", "9 AM"],
    crossingPolicy: "clamp-other-endpoint",
} as const;

const state = {
    startValue: 6,
    endValue: 8,
    available: true,
} as const;

test("ordered range parses exact Haskell-owned configuration and state", () => {
    assertDeepEqual(parseOrderedRangeConfiguration(JSON.stringify(config)), config);
    assertDeepEqual(parseOrderedRangeStateConfiguration(config, JSON.stringify(state)), state);
    assertEqual(orderedRangeLabelForValue(config, 5), "5 AM");
    assertEqual(orderedRangeLabelForValue(config, 9), "9 AM");
    assertEqual(orderedRangePositionPercent(config, 7), 50);
});

test("ordered range applies the generated clamp-other-endpoint policy in either direction", () => {
    assertDeepEqual(orderedRangeStateForInput(config, state, "start", 9), {
        startValue: 9,
        endValue: 9,
        available: true,
    });
    assertDeepEqual(orderedRangeStateForInput(config, state, "end", 5), {
        startValue: 5,
        endValue: 5,
        available: true,
    });
});

test("ordered range rejects malformed payloads without fallback labels, ranges, or state", () => {
    assertThrows(
        () => parseOrderedRangeConfiguration(JSON.stringify({ ...config, extra: true })),
        "Invalid OrderedRangeConfig",
    );
    assertThrows(
        () => parseOrderedRangeConfiguration(JSON.stringify({ ...config, valueLabels: config.valueLabels.slice(0, -1) })),
        "labels must cover every allowed value",
    );
    assertThrows(
        () => parseOrderedRangeConfiguration(JSON.stringify({ ...config, defaultStartValue: 9, defaultEndValue: 6 })),
        "default start must not exceed default end",
    );
    assertThrows(
        () => parseOrderedRangeStateConfiguration(config, JSON.stringify({ ...state, startValue: 9, endValue: 6 })),
        "start must not exceed end",
    );
    assertThrows(
        () => orderedRangeLabelForValue(config, 10),
        "value 10 is outside the configured inventory",
    );
});
