#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { repoRoot } from "./shared.mjs";
import { checkWiringRegistries } from "./wiring-registry.mjs";

const factsPath = path.join(repoRoot, "output/architecture/facts.json");
if (!fs.existsSync(factsPath)) {
  console.error("Missing output/architecture/facts.json. Run architecture-facts or architecture-check-fresh first.");
  process.exit(1);
}

const facts = JSON.parse(fs.readFileSync(factsPath, "utf8"));
const policyModules = new Set((facts.web.controllerPolicies || []).map((policy) => policy.module));
const operationKinds = new Set((facts.web.bepisArchitectureContracts?.operationKinds || facts.web.bepisArchitectureContracts?.actionKinds || []).map((kind) => kind.constructor));
const errors = checkWiringRegistries(facts);

for (const controller of facts.web.controllers || []) {
  const modules = new Set(controller.actions.map((action) => (facts.web.handlers || []).find((handler) => handler.action === action.name)?.module).filter(Boolean));
  if (![...modules].some((moduleName) => policyModules.has(moduleName))) {
    errors.push(`${controller.name} has no Bepis controller policy`);
  }
}

for (const handler of facts.web.handlers || []) {
  if (handler.kindSource !== "typed-runner") {
    errors.push(`${handler.action} is not covered by runBepis`);
    continue;
  }
  const runner = handler.bepisWrapper;
  if (!runner) {
    errors.push(`${handler.action} is missing runBepis metadata`);
    continue;
  }
  if (runner.name !== "runBepis") {
    errors.push(`${handler.action} uses unexpected Bepis runner ${runner.name}`);
  }
  if (runner.actionNameSource === "string-literal") {
    errors.push(`${handler.action} passes a string literal action name to runBepis`);
  }
  if (operationKinds.size > 0 && !operationKinds.has(runner.operationKindConstructor)) {
    errors.push(`${handler.action} uses unknown Bepis operation kind ${runner.operationKindConstructor}`);
  }
}

if (errors.length > 0) {
  console.error(`Application architecture gate failed with ${errors.length} error(s):`);
  for (const error of errors.slice(0, 50)) console.error(`- ${error}`);
  if (errors.length > 50) console.error(`... ${errors.length - 50} more`);
  process.exit(1);
}

console.log(`Application architecture gate passed: ${(facts.web.controllers || []).length} wired controllers, ${(facts.frontend?.entrypoints || []).length} wired frontend bundles, ${(facts.web.handlers || []).length} runBepis handlers.`);
