import { appPageReadyEventName, pageReadyDetailFrom } from "../app-bootstrap";
import { dialogSubmitLoadingHtml } from "../app-dialog-overlays";
import { clampHorizontalScrollLeft, parsePositiveIntegerForHorizontalScroll } from "../app-horizontal-scroll";
import { arrayBufferToBase64Url, base64UrlToArrayBuffer, localStorageKeyForPasskey } from "../app-passkeys";
import { buildTimeOptionsWithStepForRange, displayLabelFromTimeValue, minuteOfDayFromTimeValue } from "../time-picker/options";
import { assertDeepEqual, assertEqual, test } from "./harness";

test("app bootstrap preserves page-ready event contract defaults", () => {
    assertEqual(appPageReadyEventName, "app:page-ready");
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

test("time picker parses, labels, and builds stepped options", () => {
    assertEqual(minuteOfDayFromTimeValue("06:15"), 375);
    assertEqual(minuteOfDayFromTimeValue("24:00"), null);
    assertEqual(displayLabelFromTimeValue("00:00"), "12:00 AM");
    assertEqual(displayLabelFromTimeValue("13:30"), "1:30 PM");
    assertDeepEqual(buildTimeOptionsWithStepForRange({ startMinute: 60, endMinute: 90 }, 15), [
        { value: "01:00", label: "1:00 AM" },
        { value: "01:15", label: "1:15 AM" },
        { value: "01:30", label: "1:30 AM" },
    ]);
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
