import {
    parseTimePickerConfiguration,
    parseTimePickerOptionConfiguration,
    timePickerOptionsForConfiguration,
} from "../time-picker/configuration";
import { assertDeepEqual, assertThrows, test } from "./harness";

const overnightConfig = {
    rangeStart: "23:45",
    rangeEnd: "00:15",
    stepMinutes: 15,
    emptyLabel: "Start",
} as const;

const optionInventory = [
    { value: "23:30", label: "11:30 PM" },
    { value: "23:45", label: "11:45 PM" },
    { value: "00:00", label: "12:00 AM" },
    { value: "00:15", label: "12:15 AM" },
    { value: "00:30", label: "12:30 AM" },
] as const;

test("time picker parses exact generated field and option payloads", () => {
    assertDeepEqual(parseTimePickerConfiguration(JSON.stringify(overnightConfig)), overnightConfig);
    assertDeepEqual(
        parseTimePickerOptionConfiguration(JSON.stringify(optionInventory[1])),
        optionInventory[1],
    );
});

test("time picker uses the Haskell-rendered option inventory for wrapped ranges", () => {
    assertDeepEqual(timePickerOptionsForConfiguration(overnightConfig, optionInventory), [
        { value: "23:45", label: "11:45 PM" },
        { value: "00:00", label: "12:00 AM" },
        { value: "00:15", label: "12:15 AM" },
    ]);
});

test("time picker rejects malformed payloads instead of supplying fallback data or copy", () => {
    assertThrows(
        () => parseTimePickerConfiguration(JSON.stringify({ ...overnightConfig, extra: true })),
        "Invalid TimePickerConfig",
    );
    assertThrows(
        () => parseTimePickerConfiguration(JSON.stringify({ ...overnightConfig, emptyLabel: "   " })),
        "emptyLabel must not be empty",
    );
    assertThrows(
        () => parseTimePickerOptionConfiguration(JSON.stringify({ value: "23:45", label: "11:45 PM", extra: true })),
        "Invalid TimePickerOption",
    );
    assertThrows(
        () => timePickerOptionsForConfiguration(overnightConfig, optionInventory.filter((option) => option.value !== "00:00")),
        "missing rendered option 00:00",
    );
});
