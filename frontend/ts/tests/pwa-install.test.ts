import { parsePwaInstallState } from "../app-pwa";
import { assertEqual, assertThrows, test } from "./harness";

test("PWA install adapter accepts only generated closed result states", () => {
    assertEqual(parsePwaInstallState("accepted"), "accepted");
    assertEqual(parsePwaInstallState("dismissed"), "dismissed");
    assertEqual(parsePwaInstallState("failed"), "failed");
    assertThrows(() => parsePwaInstallState("web"), "Invalid PwaInstallState");
    assertThrows(() => parsePwaInstallState({ outcome: "accepted" }), "Invalid PwaInstallState");
});
