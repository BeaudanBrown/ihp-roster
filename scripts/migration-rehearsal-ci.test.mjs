import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.resolve(fileURLToPath(new URL("..", import.meta.url)));
const workflow = fs.readFileSync(path.join(root, ".github/workflows/test.yml"), "utf8");
const runbook = fs.readFileSync(path.join(root, "docs/runbooks/migration-rehearsal.md"), "utf8");

test("migration rehearsal targets actual protected and deployment branches", () => {
  assert.match(workflow, /push:\n\s+branches: \[ roster, staging, master \]/);
  assert.match(workflow, /pull_request:\n\s+branches: \[ roster, staging, master \]/);
  assert.doesNotMatch(workflow, /branches: \[ main \]/);
});

test("CI selects event predecessor authority and migration-sensitive changes", () => {
  assert.match(workflow, /github\.event\.pull_request\.base\.sha/);
  assert.match(workflow, /ref: \$\{\{ github\.sha \}\}/);
  assert.match(workflow, /github\.event\.before/);
  assert.match(workflow, /migration_predecessor:[\s\S]*?required: true/);
  assert.match(workflow, /workflow_dispatch requires migration_predecessor/);
  for (const ownedPath of [
    "Application/Schema\\.sql",
    "Application/Migration/",
    "flake\\.(nix|lock)",
    "Config/nix/flake/scripts\\.nix",
    "migration-rehearsal|test-postgres",
    "Config/nix/modules/ihp-roster\\.nix",
  ]) {
    assert.ok(workflow.includes(ownedPath), `missing CI scope: ${ownedPath}`);
  }
});

test("CI runs the shared harness and retains bounded failure evidence", () => {
  assert.match(workflow, /migration-rehearsal \\\n\s+--from-ref "\$PREDECESSOR_SHA" \\\n\s+--keep-failure-artifacts/);
  assert.match(workflow, /predecessor_commit=%s\\ncandidate_commit=%s/);
  assert.match(workflow, /migration_rehearsal_elapsed_seconds=%s target_seconds=90/);
  assert.match(workflow, /actions\/upload-artifact@v4/);
  assert.match(workflow, /\.pi\/tmp\/migration-rehearsal\/\*\*/);
});

test("operator runbook keeps rehearsal advisory and staging acceptance separate", () => {
  assert.match(runbook, /bepis-dotfiles\/flake\.lock/);
  assert.match(runbook, /migration-rehearsal --from-ref "\$PRODUCTION_REVISION"/);
  assert.match(runbook, /rozzy-staging-refresh-db/);
  assert.match(runbook, /final acceptance check for the live\s+customer-data shape/);
  assert.match(runbook, /does\s+not authorize production activation/);
  assert.match(runbook, /nixos-rebuild/);
  assert.match(runbook, /production\s+systemd blocker/);
});
