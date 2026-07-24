import { datePickerConfigFor } from "../app-date-pickers";
import { assertDeepEqual, test } from "./harness";

test("datePickerConfigFor submits ISO values and displays four-digit Australian dates", () => {
    assertDeepEqual(datePickerConfigFor("date"), {
        dateFormat: "Y-m-d",
        altInput: true,
        altFormat: "d/m/Y",
    });
    assertDeepEqual(datePickerConfigFor("datetime-local"), {
        enableTime: true,
        time_24hr: true,
        dateFormat: "Z",
        altInput: true,
        altFormat: "d/m/Y, H:i",
    });
});
