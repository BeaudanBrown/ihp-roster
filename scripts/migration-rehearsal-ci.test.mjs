import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

// Parse configuration, then execute its real selection script against disposable
// Git history. Neither YAML formatting nor runbook wording is policy evidence.
const workflow = JSON.parse(execFileSync("python3", ["-c",
  "import json, sys, yaml; json.dump(yaml.load(sys.stdin, Loader=yaml.BaseLoader), sys.stdout)",
], { input: fs.readFileSync(new URL("../.github/workflows/test.yml", import.meta.url)), encoding: "utf8" }));
const steps = workflow.jobs["migration-rehearsal"].steps;
const scope = steps.find((step) => step.id === "scope");

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "migration-ci-scope-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync("git", ["-C", root, ...args], { encoding: "utf8" }).trim();
  git("init", "-q");
  git("config", "user.email", "fixture@example.invalid");
  git("config", "user.name", "Fixture");
  const commit = (file) => {
    const target = path.join(root, file);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, `${file}\n`);
    git("add", "--", file);
    git("-c", "core.hooksPath=/dev/null", "commit", "-qm", "fixture");
    return git("rev-parse", "HEAD");
  };
  const select = (env) => {
    const output = path.join(root, "scope-output");
    fs.writeFileSync(output, "");
    const result = spawnSync("bash", ["-c", scope.run], { cwd: root, encoding: "utf8", timeout: 10_000,
      env: { ...process.env, EVENT_NAME: "push", PR_BASE_SHA: "", PUSH_BEFORE_SHA: "", MANUAL_PREDECESSOR: "", GITHUB_OUTPUT: output, ...env } });
    assert.ifError(result.error);
    return { ...result, outputs: Object.fromEntries(fs.readFileSync(output, "utf8").trim().split("\n").filter(Boolean).map((line) => line.split("="))) };
  };
  return { commit, select };
}

test("protected branches and tested candidate are selected structurally", () => {
  for (const event of ["push", "pull_request"]) assert.deepEqual(workflow.on[event].branches, ["roster", "staging", "master"]);
  assert.equal(workflow.on.workflow_dispatch.inputs.migration_predecessor.required, "true");
  assert.equal(steps.find((step) => step.uses === "actions/checkout@v4").with.ref, "${{ github.sha }}");
});

test("real Git changes select migration owners and shared tooling dependencies, not unrelated code", (t) => {
  const { commit, select } = fixture(t);
  let before = commit("README.md");
  for (const [file, expected] of [
    ["Application/Schema.sql", "true"], ["Application/Migration/fixture.sql", "true"],
    ["flake.lock", "true"], ["Config/nix/flake/tooling-packages.nix", "true"],
    ["Config/nix/flake/scripts.nix", "true"], ["tooling.project", "true"],
    ["tooling/postgres/src/Bepis/Tooling/Postgres/Rehearsal.hs", "true"],
    ["tooling/core/src/Bepis/Tooling/Core/OwnedFile.hs", "true"],
    ["tooling/workspace-state/src/Bepis/Tooling/Workspace/State.hs", "true"],
    ["Config/nix/scripts/db/migration-rehearsal-recipe", "true"],
    ["Config/nix/scripts/db/test-postgres", "true"], ["bin/tooling-run", "true"],
    ["Config/nix/modules/ihp-roster.nix", "true"], [".github/workflows/test.yml", "true"],
    ["Web/Controller/Fixture.hs", "false"], ["docs/fixture.md", "false"],
  ]) {
    const candidate = commit(file);
    const result = select({ PUSH_BEFORE_SHA: before });
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(result.outputs, { predecessor: before, candidate, run: expected }, file);
    before = candidate;
  }
});

test("PR, initial push, and manual predecessor authority is executed, including missing input failure", (t) => {
  const { commit, select } = fixture(t);
  const before = commit("README.md");
  const candidate = commit("docs/fixture.md");
  for (const env of [
    { EVENT_NAME: "pull_request", PR_BASE_SHA: before, PUSH_BEFORE_SHA: "invalid" },
    { PUSH_BEFORE_SHA: "0".repeat(40) },
    { EVENT_NAME: "workflow_dispatch", MANUAL_PREDECESSOR: before },
  ]) {
    const result = select(env);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(result.outputs, { predecessor: before, candidate, run: env.EVENT_NAME === "workflow_dispatch" ? "true" : "false" });
  }
  const missing = select({ EVENT_NAME: "workflow_dispatch" });
  assert.equal(missing.status, 64);
  assert.deepEqual(missing.outputs, {});
  assert.notEqual(select({ PUSH_BEFORE_SHA: "f".repeat(40) }).status, 0, "unavailable history must fail closed");
});
