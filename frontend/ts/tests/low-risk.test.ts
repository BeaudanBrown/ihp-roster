import { associateDatePickerLabels, datePickerConfigFor } from "../app-date-pickers";
import { assertDeepEqual, test } from "./harness";

test("date-picker enhancement labels the visible control without changing the submitted input ID", () => {
    const input = { id: "operational-date" };
    const display = { id: "" };
    const labels = [{ htmlFor: input.id }, { htmlFor: input.id }];
    associateDatePickerLabels(input, display, labels);
    assertDeepEqual(input, { id: "operational-date" });
    assertDeepEqual(labels, [{ htmlFor: display.id }, { htmlFor: display.id }]);
    assertDeepEqual(display, { id: "operational-date-date-picker-display" });
});

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
