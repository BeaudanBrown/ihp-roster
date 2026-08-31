import {
    parseDialogSubmitConfiguration,
    parseNavigationLoadingConfiguration,
} from "../app-dialog-overlays";
import { parseToastConfiguration } from "../app-toasts";
import { createDialogDismissalLifecycle } from "../dialog-overlays/lifecycle";
import { assertDeepEqual, assertEqual, assertThrows, test } from "./harness";

test("overlay adapter parses exact generated dialog submit and toast configs", () => {
    assertDeepEqual(
        parseDialogSubmitConfiguration(JSON.stringify({ loadingLabel: "Saving..." })),
        { loadingLabel: "Saving..." },
    );
    assertDeepEqual(
        parseNavigationLoadingConfiguration(JSON.stringify({
            loadingTitle: "Opening Stripe",
            loadingMessage: "Please wait while Bepis opens Stripe's secure billing page.",
        })),
        {
            loadingTitle: "Opening Stripe",
            loadingMessage: "Please wait while Bepis opens Stripe's secure billing page.",
        },
    );
    assertDeepEqual(
        parseToastConfiguration(JSON.stringify({ autoHideMs: 3200 })),
        { autoHideMs: 3200 },
    );
});

test("dialog dismissal lifecycle reconciles imperative clears and replacements exactly once", () => {
    const lifecycle = createDialogDismissalLifecycle("dialog-dismissed-test");
    const mount = new EventTarget();
    const firstDialog = new EventTarget();
    const replacementDialog = new EventTarget();
    const observed: Array<{ dialog: EventTarget; replacement: EventTarget | null }> = [];
    mount.addEventListener("dialog-dismissed-test", (event) => {
        const detail = (event as CustomEvent<{ dialog: EventTarget; replacement: EventTarget | null }>).detail;
        observed.push(detail);
    });

    lifecycle.reconcile(mount as unknown as Element, firstDialog as unknown as Element);
    assertEqual(observed.length, 0);

    lifecycle.reconcile(mount as unknown as Element, replacementDialog as unknown as Element);
    assertEqual(observed.length, 1);
    assertEqual(observed[0]?.dialog, firstDialog);
    assertEqual(observed[0]?.replacement, replacementDialog);

    lifecycle.dismiss(replacementDialog as unknown as Element, mount);
    lifecycle.dismiss(replacementDialog as unknown as Element, mount);
    lifecycle.reconcile(mount as unknown as Element, null);
    assertEqual(observed.length, 2);
    assertEqual(observed[1]?.dialog, replacementDialog);
    assertEqual(observed[1]?.replacement, null);

    lifecycle.reconcile(mount as unknown as Element, null);
    assertEqual(observed.length, 2);
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
        () => parseNavigationLoadingConfiguration(JSON.stringify({ loadingTitle: "", loadingMessage: "Waiting" })),
        "loadingTitle must not be empty",
    );
    assertThrows(
        () => parseNavigationLoadingConfiguration(JSON.stringify({ loadingTitle: "Waiting", loadingMessage: " " })),
        "loadingMessage must not be empty",
    );
    assertThrows(
        () => parseToastConfiguration(JSON.stringify({ autoHideMs: -1 })),
        "autoHideMs must not be negative",
    );
});
