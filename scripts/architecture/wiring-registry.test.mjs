import assert from "node:assert/strict";
import test from "node:test";
import { checkWiringRegistries, compareClosedRegistry } from "./wiring-registry.mjs";

const source = (path, line) => ({ path, line });
const item = (value, path, line) => ({ value, source: source(path, line) });

function fixtureFacts(overrides = {}) {
  return {
    web: {
      controllers: [
        { name: "StaticController", source: source("Web/Types.hs", 10) },
        { name: "UsersController", source: source("Web/Types.hs", 20) },
      ],
      routes: [
        { controller: "StaticController", source: source("Web/Routes.hs", 6) },
        { controller: "UsersController", source: source("Web/Routes.hs", 7) },
      ],
      frontController: {
        mounts: [
          { controller: "StaticController", source: source("Web/FrontController.hs", 30) },
          { controller: "UsersController", source: source("Web/FrontController.hs", 31) },
        ],
        websocketMounts: [
          { app: "LiveUpdatesWSApp", path: "/LiveUpdatesWSApp", source: source("Web/FrontController.hs", 32) },
        ],
      },
    },
    frontend: {
      entrypoints: [
        { path: "frontend/ts/app-bootstrap.ts", outputAsset: "/app-bootstrap.js", source: source("frontend/ts/app-bootstrap.ts", 1) },
        { path: "frontend/ts/app-roster.ts", outputAsset: "/app-roster.js", source: source("frontend/ts/app-roster.ts", 1) },
      ],
      layoutScripts: [
        { asset: "/app-bootstrap.js", source: source("Web/View/Layout.hs", 300) },
        { asset: "/app-roster.js", source: source("Web/View/Layout.hs", 301) },
      ],
    },
    wiringRegistryPolicy: {
      controllerRouteExceptions: [],
      controllerMountExceptions: [],
      frontendLayoutExceptions: [],
    },
    ...overrides,
  };
}

test("closed registry comparison diagnoses missing, extra, and duplicate values with source provenance", () => {
  const errors = compareClosedRegistry({
    registry: "fixture registry",
    canonical: [item("Alpha", "Canonical.hs", 4), item("Beta", "Canonical.hs", 8)],
    registered: [item("Alpha", "Registry.hs", 3), item("Gamma", "Registry.hs", 9), item("Gamma", "Registry.hs", 12)],
  });

  assert.deepEqual(errors, [
    "fixture registry: missing Beta declared at Canonical.hs:8",
    "fixture registry: extra Gamma registered at Registry.hs:9, Registry.hs:12",
    "fixture registry: duplicate Gamma registered at Registry.hs:9, Registry.hs:12",
  ]);
});

test("controller checker rejects a declared controller missing from routes", () => {
  const facts = fixtureFacts();
  facts.web.routes.pop();
  assert.deepEqual(checkWiringRegistries(facts), [
    "controller routes: missing UsersController declared at Web/Types.hs:20",
  ]);
});

test("controller checker rejects an extra and duplicate front-controller mount", () => {
  const facts = fixtureFacts();
  facts.web.frontController.mounts.push(
    { controller: "GhostController", source: source("Web/FrontController.hs", 40) },
    { controller: "StaticController", source: source("Web/FrontController.hs", 41) },
  );
  assert.deepEqual(checkWiringRegistries(facts), [
    "controller mounts: extra GhostController registered at Web/FrontController.hs:40",
    "controller mounts: duplicate StaticController registered at Web/FrontController.hs:30, Web/FrontController.hs:41",
  ]);
});

test("frontend checker rejects a globally built bundle missing from Layout", () => {
  const facts = fixtureFacts();
  facts.frontend.layoutScripts.pop();
  assert.deepEqual(checkWiringRegistries(facts), [
    "frontend Layout scripts: missing /app-roster.js declared at frontend/ts/app-roster.ts:1",
  ]);
});

test("frontend checker rejects extra and duplicate Layout app scripts", () => {
  const facts = fixtureFacts();
  facts.frontend.layoutScripts.push(
    { asset: "/app-ghost.js", source: source("Web/View/Layout.hs", 302) },
    { asset: "/app-bootstrap.js", source: source("Web/View/Layout.hs", 303) },
  );
  assert.deepEqual(checkWiringRegistries(facts), [
    "frontend Layout scripts: extra /app-ghost.js registered at Web/View/Layout.hs:302",
    "frontend Layout scripts: duplicate /app-bootstrap.js registered at Web/View/Layout.hs:300, Web/View/Layout.hs:303",
  ]);
});

test("documented frontend exceptions exclude intentionally non-global bundles", () => {
  const facts = fixtureFacts();
  facts.frontend.layoutScripts.pop();
  facts.wiringRegistryPolicy.frontendLayoutExceptions = [
    { value: "/app-roster.js", owner: "frontend", reason: "Loaded only by a feature-specific shell", source: source("scripts/architecture/wiring-policy.mjs", 20) },
  ];
  assert.deepEqual(checkWiringRegistries(facts), []);
});

test("unused or duplicate exceptions fail instead of hiding policy drift", () => {
  const facts = fixtureFacts();
  facts.wiringRegistryPolicy.frontendLayoutExceptions = [
    { value: "/app-ghost.js", owner: "frontend", reason: "No longer valid", source: source("scripts/architecture/wiring-policy.mjs", 20) },
    { value: "/app-ghost.js", owner: "frontend", reason: "Duplicate", source: source("scripts/architecture/wiring-policy.mjs", 21) },
  ];
  assert.deepEqual(checkWiringRegistries(facts), [
    "frontend Layout scripts exceptions: duplicate /app-ghost.js registered at scripts/architecture/wiring-policy.mjs:20, scripts/architecture/wiring-policy.mjs:21",
    "frontend Layout scripts exceptions: unused /app-ghost.js declared at scripts/architecture/wiring-policy.mjs:20, scripts/architecture/wiring-policy.mjs:21",
  ]);
});

test("exceptions require an accountable owner and a reason", () => {
  const facts = fixtureFacts();
  facts.frontend.layoutScripts.pop();
  facts.wiringRegistryPolicy.frontendLayoutExceptions = [
    { value: "/app-roster.js", owner: "", reason: "", source: source("scripts/architecture/wiring-policy.mjs", 20) },
  ];
  assert.deepEqual(checkWiringRegistries(facts), [
    "frontend Layout scripts exceptions: /app-roster.js has no owner at scripts/architecture/wiring-policy.mjs:20",
    "frontend Layout scripts exceptions: /app-roster.js has no reason at scripts/architecture/wiring-policy.mjs:20",
  ]);
});
