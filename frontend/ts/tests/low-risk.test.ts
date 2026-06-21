import { datePickerConfigFor } from "../app-date-pickers";
import { formatHour } from "../app-preferences";
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

test("formatHour formats shift preference hour labels", () => {
    assertEqual(formatHour("0"), "12 AM");
    assertEqual(formatHour("5"), "5 AM");
    assertEqual(formatHour("12"), "12 PM");
    assertEqual(formatHour("23"), "11 PM");
    assertEqual(formatHour("not-an-hour"), "");
});
