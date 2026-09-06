import assert from "node:assert/strict";
import test from "node:test";
import { inspectWorkflowBoundaries, workflowImports, workflowViolationMessage } from "./workflow-boundaries.mjs";

const roles = [
  ["Web.Pilot.Workflow", "workflow", "Pilot"],
  ["Web.Pilot.Responses", "response", "Pilot"],
  ["Web.Pilot.Mutations", "mutation", "Pilot"],
  ["Application.Pilot", "application", "Pilot"],
];
const typeException = {
  name: "pilot-result", module: "Web.Pilot.Responses", dependency: "Web.Pilot.Mutations",
  onlyTypes: ["Result"], owner: "Pilot", reason: "Completion reads a committed result type, not a writer.",
};
function inspect(module, imports, exceptions = []) {
  return inspectWorkflowBoundaries((sourcePath) => {
    const name = sourcePath.replaceAll("/", ".").replace(/\.hs$/, "");
    return `module ${name} where\n${name === module ? imports : ""}\n`;
  }, roles, exceptions);
}

for (const [rule, module, allowed, denied] of [
  ["application-web-dependency", "Application.Pilot", "IHP.ControllerPrelude", "Web.Pilot.Mutations"],
  ["mutation-presentation-dependency", "Web.Pilot.Mutations", "Web.Controller.Prelude", "Web.Pilot.Workflow"],
  ["mutation-presentation-dependency", "Web.Pilot.Mutations", "Web.SurfaceInvalidation", "Web.Pilot.Responses"],
  ["mutation-presentation-dependency", "Web.Pilot.Mutations", "Application.Pilot", "Web.View.Pilot.Show"],
  ["workflow-response-dependency", "Web.Pilot.Workflow", "Web.Pilot.Mutations", "Web.Pilot.Responses"],
  ["response-mutation-dependency", "Web.Pilot.Responses", "Web.Pilot.Workflow", "Web.Pilot.Mutations"],
  ...["Web.Pilot.Workflow", "Web.Pilot.Responses"].flatMap((module) => [
    "Web.SurfaceInvalidation", "Application.Helper.LiveUpdate.DurablePublisher", "Application.Helper.LiveUpdate.Runtime",
  ].map((denied) => ["request-passive-publisher-dependency", module, "Application.Helper.LiveUpdate", denied])),
]) {
  test(`${rule}: ${module} allows ${allowed} but rejects ${denied}`, () => {
    assert.deepEqual(inspect(module, `import ${allowed}`).violations, []);
    const { violations } = inspect(module, `-- import ${denied}\nimport qualified ${denied} as Forbidden`);
    assert.equal(violations.length, 1);
    assert.equal(violations[0].rule, rule);
    assert.equal(violations[0].owner, "Pilot");
    assert.deepEqual(violations[0].source, { path: `${module.replaceAll(".", "/")}.hs`, line: 3 });
    assert.match(workflowViolationMessage(violations[0]), /:3 \[.*owner=Pilot\].*must not import/);
  });
}

test("multiline, post-qualified, package and SOURCE imports retain provenance; nested comments are ignored", () => {
  const imports = workflowImports(`-- import Web.Fake
{- import Web.Fake {- nested -} -}
module Fixture where
import {-# SOURCE #-} safe "bepis" Web.Pilot.Mutations qualified as M
    ( Result
    )
import
    qualified Web.Pilot.Responses as R
`, "Fixture.hs");
  assert.deepEqual(imports.map(({ dependency, names, source }) => [dependency, names, source.line]), [
    ["Web.Pilot.Mutations", ["Result"], 4], ["Web.Pilot.Responses", null, 7],
  ]);
});

test("type-only exception permits the exact result import, including comments and qualification", () => {
  const result = inspect("Web.Pilot.Responses", "import qualified Web.Pilot.Mutations as M\n  ( {- a type -} type\n Result )", [typeException]);
  assert.deepEqual(result.violations, []);
  assert.deepEqual(result.exceptions, [typeException]);
});

for (const suffix of ["", " hiding (write)", " (type Result, write)", " (type Result(..))", " ()", " (Result)", " (pattern Result)"]) {
  test(`type-only exception cannot authorize mutation operations via '${suffix}'`, () => {
    assert.ok(inspect("Web.Pilot.Responses", `import Web.Pilot.Mutations${suffix}`, [typeException]).violations
      .some(({ rule }) => rule === "response-mutation-dependency"));
  });
}

for (const field of ["name", "owner", "reason"]) {
  test(`exception requires ${field}`, () => {
    assert.ok(inspect("Web.Pilot.Responses", "import Web.Pilot.Mutations (type Result)", [{ ...typeException, [field]: " " }]).violations
      .some(({ rule }) => rule === "workflow-exception"));
  });
}

test("duplicate, stale, unknown, or value-shaped exceptions fail closed", () => {
  for (const exceptions of [
    [typeException, typeException],
    [typeException, { ...typeException, name: "duplicate-selector" }],
    [{ ...typeException, dependency: "Web.Unknown.Mutations" }],
    [{ ...typeException, onlyTypes: ["write"] }],
    [{ ...typeException, onlyTypes: ["Result", "Result"] }],
  ]) {
    assert.ok(inspect("Web.Pilot.Responses", "import Web.Pilot.Mutations (type Result)", exceptions).violations
      .some(({ rule }) => rule === "workflow-exception"));
  }
  assert.match(inspect("Web.Pilot.Responses", "", [typeException]).violations[0].message, /Stale.*pilot-result/);
});

test("missing, renamed, duplicate and unowned adopted modules cannot silently lose enforcement", () => {
  const missing = inspectWorkflowBoundaries(() => { throw new Error("missing"); }, roles, []);
  assert.equal(missing.violations.length, roles.length);
  assert.ok(missing.violations.every(({ rule }) => rule === "workflow-source"));
  assert.ok(inspectWorkflowBoundaries(() => "module Wrong where", roles, []).violations.every(({ rule }) => rule === "workflow-source"));
  for (const invalid of [[...roles, roles[0]], [["Web.Pilot.Workflow", "workflow", ""]], [["Web.Pilot.Workflow", "empty-layer", "Pilot"]]]) {
    assert.ok(inspectWorkflowBoundaries(() => "module Web.Pilot.Workflow where", invalid, []).violations.some(({ rule }) => rule === "workflow-policy"));
  }
});

test("both delivered pilots and the existing Billing phase adapter fit the import contract", () => {
  const result = inspectWorkflowBoundaries();
  assert.deepEqual(result.violations, []);
  assert.ok(result.modules.some(({ module }) => module === "Application.Billing.Checkout"));
  for (const name of ["EntryWorkflow", "Responses", "Mutations"]) {
    assert.ok(result.modules.some(({ module, owner }) => module === `Web.Timesheets.${name}` && owner === "Timesheets"));
  }
});
