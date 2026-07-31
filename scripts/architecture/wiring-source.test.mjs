import assert from "node:assert/strict";
import test from "node:test";
import {
  parseControllerMounts,
  parseControllerRoutes,
  parseFrontendLayoutScripts,
} from "./wiring-source.mjs";

test("route extraction ignores commented AutoRoute text", () => {
  const routes = parseControllerRoutes(`
instance AutoRoute StaticController
-- instance AutoRoute CommentedController
-- Mention: instance AutoRoute ProseController
instance AutoRoute E2ETestController where
    customRoutes = pure MarkE2EPasskeyVerifiedAction
`);
  assert.deepEqual(routes.map((route) => route.controller), ["StaticController", "E2ETestController"]);
  assert.deepEqual(routes.map((route) => route.source.line), [2, 5]);
});

test("mount extraction reads only active parseRoute entries in the controllers list", () => {
  const mounts = parseControllerMounts(`
helper = parseRoute @HelperController
instance FrontController WebApplication where
    controllers =
        [ parseRoute @StaticController
        -- , parseRoute @CommentedController
        , parseRoute @UsersController
        , webSocketAppWithCustomPath @LiveUpdatesWSApp socketPath
        ]
other = parseRoute @OtherController
`);
  assert.deepEqual(mounts.map((mount) => mount.controller), ["StaticController", "UsersController"]);
  assert.deepEqual(mounts.map((mount) => mount.source.line), [5, 7]);
});

test("Layout extraction counts only app assets used as script sources", () => {
  const scripts = parseFrontendLayoutScripts(`
<link rel="preload" href={assetPath "/app-preload.js"}/>
-- <script src={assetPath "/app-commented.js"}></script>
<script defer src={assetPath "/app-bootstrap.js"}></script>
<div data-bundle={assetPath "/app-metadata.js"}></div>
<script src={assetPath "/app-roster.js"} data-owner="roster"></script>
`);
  assert.deepEqual(scripts.map((script) => script.asset), ["/app-bootstrap.js", "/app-roster.js"]);
  assert.deepEqual(scripts.map((script) => script.source.line), [4, 6]);
});
