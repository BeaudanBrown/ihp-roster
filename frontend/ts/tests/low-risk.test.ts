import { datePickerConfigFor } from "../app-date-pickers";
import { assertDeepEqual, test } from "./harness";

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
