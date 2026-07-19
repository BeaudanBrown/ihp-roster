import {
    parseHorizontalDragConfiguration,
    parseHorizontalSnapConfiguration,
} from "../horizontal-scroll/configuration";
import { assertDeepEqual, assertThrows, test } from "./harness";

test("horizontal scroll parses exact generated nearest-item and equal-group configurations", () => {
    assertDeepEqual(parseHorizontalSnapConfiguration(JSON.stringify({
        snapMode: "nearest-item",
        itemSelector: ".timesheet-day-panel",
        groupCount: null,
        groupProperty: null,
        groupScopeSelector: null,
    })), {
        snapMode: "nearest-item",
        itemSelector: ".timesheet-day-panel",
        groupCount: null,
        groupProperty: null,
        groupScopeSelector: null,
    });
    assertDeepEqual(parseHorizontalSnapConfiguration(JSON.stringify({
        snapMode: "equal-groups",
        itemSelector: null,
        groupCount: null,
        groupProperty: "--roster-slot-count",
        groupScopeSelector: ".roster-grid-frame",
    })), {
        snapMode: "equal-groups",
        itemSelector: null,
        groupCount: null,
        groupProperty: "--roster-slot-count",
        groupScopeSelector: ".roster-grid-frame",
    });
    assertDeepEqual(parseHorizontalDragConfiguration('{"ignoreSelector":null}'), { ignoreSelector: null });
});

test("horizontal scroll rejects malformed and contradictory generated configurations", () => {
    assertThrows(() => parseHorizontalSnapConfiguration(JSON.stringify({
        snapMode: "nearest-item",
        itemSelector: null,
        groupCount: null,
        groupProperty: null,
        groupScopeSelector: null,
    })), "requires itemSelector");
    assertThrows(() => parseHorizontalSnapConfiguration(JSON.stringify({
        snapMode: "equal-groups",
        itemSelector: null,
        groupCount: 7,
        groupProperty: "--count",
        groupScopeSelector: ".frame",
    })), "exactly one group source");
    assertThrows(() => parseHorizontalDragConfiguration('{"ignoreSelector":"","extra":true}'), "Invalid HorizontalDragConfig");
});
