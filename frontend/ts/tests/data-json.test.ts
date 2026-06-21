import type { OverlayLane } from "../generated/contracts";
import { readJsonScriptElement, type JsonScriptRoot } from "../shared/data-json";
import { assertDeepEqual, assertEqual, assertThrows, test } from "./harness";

function rootWith(element: { textContent: string | null; type: string } | null): JsonScriptRoot {
    return {
        querySelector(selector: string) {
            assertEqual(selector, "[data-contract]");
            return element;
        },
    };
}

test("readJsonScriptElement parses backend-owned JSON script payloads", () => {
    type OverlayPayload = { lane: OverlayLane; mountId: string };

    const payload = readJsonScriptElement<OverlayPayload>(
        rootWith({ textContent: '{"lane":"dialog","mountId":"modal-root"}', type: "application/json" }),
        "[data-contract]",
    );

    assertDeepEqual(payload, { lane: "dialog", mountId: "modal-root" });
});

test("readJsonScriptElement returns null for missing or empty payloads", () => {
    assertEqual(readJsonScriptElement(rootWith(null), "[data-contract]"), null);
    assertEqual(readJsonScriptElement(rootWith({ textContent: "  ", type: "application/json" }), "[data-contract]"), null);
});

test("readJsonScriptElement rejects non-json script elements", () => {
    assertThrows(
        () => readJsonScriptElement(rootWith({ textContent: "{}", type: "text/javascript" }), "[data-contract]"),
        "application/json",
    );
});
