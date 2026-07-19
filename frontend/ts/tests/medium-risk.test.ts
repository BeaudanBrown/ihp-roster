import { appPageReadyEventName, pageReadyDetailFrom } from "../app-bootstrap";
import { dialogSubmitLoadingHtml } from "../app-dialog-overlays";
import { pageReadyEvent } from "../generated/contracts";
import { clampHorizontalScrollLeft, parsePositiveIntegerForHorizontalScroll } from "../horizontal-scroll/math";
import { arrayBufferToBase64Url, base64UrlToArrayBuffer } from "../passkeys/base64url";
import { localStorageKeyForPasskey } from "../passkeys/storage";
import { assertDeepEqual, assertEqual, test } from "./harness";

test("app bootstrap preserves page-ready event contract defaults", () => {
    assertEqual(appPageReadyEventName, pageReadyEvent);
    assertDeepEqual(pageReadyDetailFrom({ source: "htmx-after-swap", isFullPage: false }), {
        source: "htmx-after-swap",
        isFullPage: false,
    });
    assertDeepEqual(pageReadyDetailFrom({}), { source: "unknown", isFullPage: false });
});

test("dialog overlay loading HTML keeps spinner and label", () => {
    assertEqual(
        dialogSubmitLoadingHtml("Saving..."),
        '<span class="spinner-border spinner-border-sm" aria-hidden="true"></span><span>Saving...</span>'
    );
});

test("passkey helpers preserve storage key and base64url roundtrip", () => {
    assertEqual(localStorageKeyForPasskey("user-1", "passkeySeen"), "ihpRoster.passkeySeen.user-1");
    const bytes = new Uint8Array([251, 255, 0, 1]);
    const encoded = arrayBufferToBase64Url(bytes.buffer);
    assertEqual(encoded, "-_8AAQ");
    assertDeepEqual(Array.from(new Uint8Array(base64UrlToArrayBuffer(encoded))), [251, 255, 0, 1]);
});

test("horizontal scroll helpers parse positive integers and clamp scroll positions", () => {
    assertEqual(parsePositiveIntegerForHorizontalScroll("3"), 3);
    assertEqual(parsePositiveIntegerForHorizontalScroll("0"), null);
    assertEqual(parsePositiveIntegerForHorizontalScroll("bad"), null);
    assertEqual(clampHorizontalScrollLeft(-10, 500, 100), 0);
    assertEqual(clampHorizontalScrollLeft(450, 500, 100), 400);
    assertEqual(clampHorizontalScrollLeft(250, 500, 100), 250);
});
