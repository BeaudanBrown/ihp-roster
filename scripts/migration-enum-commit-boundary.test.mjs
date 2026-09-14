import assert from "node:assert/strict";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(fileURLToPath(new URL("..", import.meta.url)));
const policyScript = path.join(repositoryRoot, "scripts/migration-enum-commit-boundary.mjs");
const fixturesRoot = path.join(repositoryRoot, "Test/Fixtures/migration-enum-commit-boundary");

function runFixture(name) {
  return spawnSync(process.execPath, [policyScript, "--root", path.join(fixturesRoot, name)], {
    encoding: "utf8",
  });
}

test("rejects the original combined 1788400000 enum-add and use shape", () => {
  const result = runFixture("combined");

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /1788400000\.sql/);
  assert.match(result.stderr, /SQLSTATE 55P04/);
  assert.match(result.stderr, /pinned IHP runner/);
  assert.match(result.stderr, /later migration revision/);
  assert.match(result.stderr, /real-runner migration rehearsal remains authoritative/);
});

test("accepts an isolated enum addition followed by a later-use revision", () => {
  const result = runFixture("split");

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /2 migrations, 1 enum-add migrations/);
});

test("accepts unrelated SQL and ignores comments and quoted contents", () => {
  const result = runFixture("unrelated");

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /1 migrations, 0 enum-add migrations/);
});
