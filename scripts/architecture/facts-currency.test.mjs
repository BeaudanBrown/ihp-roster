import assert from "node:assert/strict";
import test from "node:test";
import { architectureFactInputFiles } from "./facts-currency.mjs";

test("architecture fact inputs use authored frontend sources instead of generated static bundles", () => {
  const inputs = architectureFactInputFiles();
  assert.ok(inputs.some((file) => file.startsWith("frontend/ts/") && file.endsWith(".ts")));
  assert.equal(inputs.some((file) => file.startsWith("static/") && file.endsWith(".js")), false);
  assert.ok(inputs.includes("output/architecture/bepis-contracts.json"));
  assert.ok(inputs.includes("scripts/architecture/workflow-boundaries.mjs"));
});
