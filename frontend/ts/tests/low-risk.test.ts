import { datePickerConfigFor } from "../app-date-pickers";
import { fuzzyIncludes } from "../app-xero";
import { assertDeepEqual, assertEqual, test } from "./harness";

test("fuzzyIncludes supports contiguous and ordered non-contiguous matches", () => {
    assertEqual(fuzzyIncludes("ordinary earnings", "earn"), true);
    assertEqual(fuzzyIncludes("ordinary earnings", "odg"), true);
    assertEqual(fuzzyIncludes("ordinary earnings", "zzz"), false);
    assertEqual(fuzzyIncludes("ordinary earnings", ""), true);
});

test("datePickerConfigFor preserves date and datetime picker options", () => {
    assertDeepEqual(datePickerConfigFor("date"), { altFormat: "d.m.y" });
    assertDeepEqual(datePickerConfigFor("datetime-local"), {
        enableTime: true,
        time_24hr: true,
        dateFormat: "Z",
        altInput: true,
        altFormat: "d.m.y, H:i",
    });
});
