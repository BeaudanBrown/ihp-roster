import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { repoRoot } from "./shared.mjs";

const maxStructuredQueryBytes = 20_000;

function runGeneratedContractsQuery(target, includeConsumers) {
  const result = spawnSync("node", ["scripts/architecture/query.mjs"], {
    cwd: repoRoot,
    encoding: "utf8",
    input: `${JSON.stringify({
      name: "generated-contracts",
      args: { target, includeConsumers },
    })}\n`,
  });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.ok(
    Buffer.byteLength(result.stdout) < maxStructuredQueryBytes,
    `generated-contracts query output exceeds ${maxStructuredQueryBytes} bytes`,
  );
  return JSON.parse(result.stdout);
}

test("generated-contracts query keeps structured output bounded and focused", () => {
  const allSurfaces = runGeneratedContractsQuery("all", true);
  assert.ok(allSurfaces.tables.find((table) => table.title === "reflected surfaces").rows.length > 1);

  const withConsumers = runGeneratedContractsQuery("roster", true);
  const reflectedSurfaces = withConsumers.tables.find((table) => table.title === "reflected surfaces");
  assert.deepEqual(reflectedSurfaces.rows.map((row) => row.surface), ["roster"]);

  const consumerFiles = withConsumers.tables.find((table) => table.title === "consumer files");
  assert.ok(consumerFiles.rows.length <= 20);
  assert.ok(withConsumers.warnings.some((warning) => warning.includes("consumer files omitted")));

  const withoutConsumers = runGeneratedContractsQuery("roster", false);
  assert.equal(withoutConsumers.tables.some((table) => table.title === "consumer groups"), false);
  assert.equal(withoutConsumers.tables.some((table) => table.title === "consumer files"), false);
});
