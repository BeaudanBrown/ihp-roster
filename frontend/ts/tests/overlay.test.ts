import { parseDialogSubmitConfiguration } from "../app-dialog-overlays";
import { parseToastConfiguration } from "../app-toasts";
import { assertDeepEqual, assertThrows, test } from "./harness";

test("overlay adapter parses exact generated dialog submit and toast configs", () => {
    assertDeepEqual(
        parseDialogSubmitConfiguration(JSON.stringify({ loadingLabel: "Saving..." })),
        { loadingLabel: "Saving..." },
    );
    assertDeepEqual(
        parseToastConfiguration(JSON.stringify({ autoHideMs: 3200 })),
        { autoHideMs: 3200 },
    );
});

test("overlay adapter rejects malformed or semantically invalid generated configs", () => {
    assertThrows(
        () => parseDialogSubmitConfiguration(JSON.stringify({ loadingLabel: "Saving...", extra: true })),
        "Invalid DialogSubmitConfig",
    );
    assertThrows(
        () => parseDialogSubmitConfiguration(JSON.stringify({ loadingLabel: "   " })),
        "loadingLabel must not be empty",
    );
    assertThrows(
        () => parseToastConfiguration(JSON.stringify({ autoHideMs: -1 })),
        "autoHideMs must not be negative",
    );
});
