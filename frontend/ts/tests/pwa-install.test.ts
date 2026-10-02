import { detectInstallEnvironment, selectedInstallGuides, parsePwaInstallState } from "../app-pwa";
import { assertEqual, assertThrows, test } from "./harness";

test("PWA device detection is conservative and handles desktop-mode iPad", () => {
    for (const [ua, platform, touch, device, browser] of [
        ["iPhone Version/18 Safari/605", "iPhone", 5, "ios", "safari"],
        ["Macintosh Version/18 Safari/605", "MacIntel", 5, "ios", "safari"],
        ["Android Chrome/140", "Linux arm", 5, "android", "chrome"],
        ["Windows Chrome/140 Edg/140", "Win32", 0, "windows", "edge"],
        ["Windows Firefox/143", "Win32", 0, "windows", "firefox"],
        ["Macintosh Version/18 Safari/605", "MacIntel", 0, "mac", "safari"],
        ["Linux Firefox/143", "Linux", 0, "linux", "firefox"],
        ["Android; wv) Chrome/140", "Linux arm", 5, "android", "general"],
        ["Instagram iPhone", "iPhone", 5, "ios", "general"],
        ["mystery", "", 0, "general", "general"],
    ] as const) {
        const detected = detectInstallEnvironment(ua, platform, touch);
        assertEqual(detected.device, device);
        assertEqual(detected.browser, browser);
    }
});

test("PWA guidance keeps supported-browser alternatives without claiming prompt absence means unsupported", () => {
    assertEqual(selectedInstallGuides("windows", "firefox").join(","), "windows,firefox");
    assertEqual(selectedInstallGuides("mac", "safari").join(","), "mac,safari");
    assertEqual(selectedInstallGuides("linux", "firefox").join(","), "linux,chrome,edge,general");
    assertEqual(selectedInstallGuides("general", "chrome").join(","), "general");
    assertEqual(selectedInstallGuides("ios", "chrome").join(","), "ios");
});

test("PWA install adapter accepts only generated closed result states", () => {
    assertEqual(parsePwaInstallState("accepted"), "accepted");
    assertEqual(parsePwaInstallState("dismissed"), "dismissed");
    assertEqual(parsePwaInstallState("failed"), "failed");
    assertThrows(() => parsePwaInstallState("web"), "Invalid PwaInstallState");
    assertThrows(() => parsePwaInstallState({ outcome: "accepted" }), "Invalid PwaInstallState");
});
