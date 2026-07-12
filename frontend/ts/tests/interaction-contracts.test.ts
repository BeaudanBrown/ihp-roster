import {
    FrontendSurfaceInteractionRegistry,
    InteractionDom,
    isFrontendSurfaceInteractionSurfaceName,
    type InteractionSessionEffect,
} from "../generated/contracts";
import { assertDeepEqual, assertEqual, test } from "./harness";

test("generated interaction DOM vocabulary is shared with Haskell renderers", () => {
    assertEqual(InteractionDom.attributes.intentField, "data-bepis-intent-field"); // frontend-contract-token-fixture
    assertEqual(InteractionDom.attributes.sourceKey, "data-bepis-source-key"); // frontend-contract-token-fixture
    assertEqual(InteractionDom.attributes.dropzoneKey, "data-bepis-dropzone-key"); // frontend-contract-token-fixture
    assertEqual(InteractionDom.attributes.interactionActive, "data-bepis-interaction-active"); // frontend-contract-token-fixture
});

test("generated interaction registry exposes only browser-consumed roster semantics", () => {
    assertEqual(isFrontendSurfaceInteractionSurfaceName("roster"), true);
    assertEqual(isFrontendSurfaceInteractionSurfaceName("timesheets"), false);

    const roster = FrontendSurfaceInteractionRegistry.roster;
    assertEqual(roster.sessionKinds[0]?.kind, "drag");
    assertDeepEqual(roster.sessionKinds[0]?.effects.global, [
        { className: "bepis-pointer-clone-shadow", kind: "clone-shadow", layer: "drag-preview", preserveGrabOffset: true, source: "pointer-marker" },
    ]);
    assertDeepEqual(roster.sessionKinds[0]?.effects.contextual, [
        { className: "bepis-dropzone-highlight", kind: "dropzone-highlight" },
    ]);
    assertEqual(roster.sourceRefs[0]?.intent, "move-roster-shift-to-slot");
    assertEqual(roster.dropzoneRefs[0]?.targetField, "targetDropzoneKey");
    assertEqual(roster.activationRefs[0]?.trigger, "click");
});

test("generated interaction effects remain exhaustively typed without unused codecs", () => {
    const effect: InteractionSessionEffect = { kind: "dropzone-highlight", className: "bepis-dropzone-highlight" };
    assertDeepEqual(effect, { kind: "dropzone-highlight", className: "bepis-dropzone-highlight" });
});
