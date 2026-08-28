import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { architectureFactFingerprint, architectureFactsRecoveryCommand } from "./facts-currency.mjs";
import { repoRoot } from "./shared.mjs";

const maxStructuredQueryBytes = 20_000;
const queryScript = path.join(repoRoot, "scripts/architecture/query.mjs");

function runQuery(cwd, payload) {
  return spawnSync(process.execPath, [queryScript], {
    cwd,
    encoding: "utf8",
    input: `${JSON.stringify(payload)}\n`,
  });
}

function runGeneratedContractsQuery(target, includeConsumers) {
  const result = runQuery(repoRoot, {
    name: "generated-contracts",
    args: { target, includeConsumers },
  });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.ok(
    Buffer.byteLength(result.stdout) < maxStructuredQueryBytes,
    `generated-contracts query output exceeds ${maxStructuredQueryBytes} bytes`,
  );
  return JSON.parse(result.stdout);
}

test("focused queries reject stale facts and leave current facts untouched", (t) => {
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "architecture-query-currency-"));
  t.after(() => fs.rmSync(fixtureRoot, { recursive: true, force: true }));
  fs.mkdirSync(path.join(fixtureRoot, "Application"), { recursive: true });
  fs.mkdirSync(path.join(fixtureRoot, "output/architecture"), { recursive: true });
  const schemaPath = path.join(fixtureRoot, "Application/Schema.sql");
  const contractsPath = path.join(fixtureRoot, "output/architecture/bepis-contracts.json");
  const schemaSource = "CREATE TABLE fixture (id UUID);\n";
  fs.writeFileSync(schemaPath, schemaSource);
  fs.writeFileSync(contractsPath, "{\"version\":1}\n");

  const factsPath = path.join(fixtureRoot, "output/architecture/facts.json");
  const facts = {
    version: 3,
    inputFingerprint: architectureFactFingerprint(fixtureRoot),
    schema: { tables: [], enums: [] },
    web: { controllers: [], handlers: [], controllerPolicies: [] },
    modules: [],
    realtime: { surfaces: [], references: [] },
    frontend: { contracts: { sources: [], generated: [], consumers: [] } },
  };
  fs.writeFileSync(factsPath, `${JSON.stringify(facts, null, 2)}\n`);
  const currentFacts = fs.readFileSync(factsPath, "utf8");

  const currentResult = runQuery(fixtureRoot, { name: "conventions", args: {} });
  assert.equal(currentResult.status, 0, currentResult.stderr || currentResult.stdout);
  assert.equal(fs.readFileSync(factsPath, "utf8"), currentFacts, "current facts should not be regenerated");

  fs.appendFileSync(schemaPath, "-- representative source mutation\n");
  const staleSourceResult = runQuery(fixtureRoot, { name: "conventions", args: {} });
  assert.notEqual(staleSourceResult.status, 0, "stale source facts must not produce a successful query");
  assert.match(staleSourceResult.stderr, /Stale output\/architecture\/facts\.json/);
  assert.match(staleSourceResult.stderr, /Application\/Schema\.sql/);
  assert.match(staleSourceResult.stderr, new RegExp(architectureFactsRecoveryCommand.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));

  fs.writeFileSync(schemaPath, schemaSource);
  fs.writeFileSync(contractsPath, "{\"version\":2}\n");
  const staleContractResult = runQuery(fixtureRoot, { name: "conventions", args: {} });
  assert.notEqual(staleContractResult.status, 0, "stale contract facts must not produce a successful query");
  assert.match(staleContractResult.stderr, /output\/architecture\/bepis-contracts\.json/);
});

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
