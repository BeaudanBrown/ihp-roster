import { rosterFullscreenLabels } from "../roster/fullscreen";
import { assertDeepEqual, test } from "./harness";

test("roster fullscreen labels preserve aria and icon state", () => {
    assertDeepEqual(rosterFullscreenLabels(false), {
        pressed: "false",
        label: "Expand roster",
        iconAdd: "bi-fullscreen",
        iconRemove: "bi-fullscreen-exit",
    });
    assertDeepEqual(rosterFullscreenLabels(true), {
        pressed: "true",
        label: "Exit expanded roster",
        iconAdd: "bi-fullscreen-exit",
        iconRemove: "bi-fullscreen",
    });
});
