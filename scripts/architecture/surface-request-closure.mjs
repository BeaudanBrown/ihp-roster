#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { repoRoot } from "./shared.mjs";

const factsPath = path.join(repoRoot, "output/architecture/facts.json");
if (!fs.existsSync(factsPath)) {
  console.error("Missing output/architecture/facts.json. Run architecture-facts first.");
  process.exit(1);
}

const facts = JSON.parse(fs.readFileSync(factsPath, "utf8"));
const modulesByName = new Map((facts.modules || []).map((module) => [module.name, module]));

const sharedRequestRuntimeClosure = [
  "Application.Helper.FrontendContract.ClosedScalar",
  "Application.Helper.FrontendContract.Core",
  "Application.Helper.FrontendContract.DSL",
  "Application.Helper.FrontendContract.Interaction",
  "Application.Helper.FrontendContract.Naming",
  "Application.Helper.FrontendContract.Surface.ContractIR",
  "Application.Helper.FrontendContract.Surface.Diagnostics",
  "Application.Helper.FrontendContract.Surface.DSL",
  "Application.Helper.FrontendContract.Surface.HaskellAdapter.Association",
  "Application.Helper.FrontendContract.Surface.Reflect",
  "Application.Helper.FrontendContract.Surface.Request",
  "Application.Helper.FrontendContract.Surface.Request.Runtime",
  "Application.Helper.FrontendContract.Surface.Request.Runtime.Internal",
  "Application.Helper.FrontendContract.Surface.SemanticIR",
  "Application.Helper.FrontendContract.Surface.Values",
];

const closureContracts = [
  {
    label: "Surface.Roster.Action",
    root: "Application.Helper.FrontendContract.Surface.Roster.Action",
    expected: [
      ...sharedRequestRuntimeClosure,
      "Application.Helper.FrontendContract.Surface.Interaction",
      "Application.Helper.FrontendContract.Surface.LeaveRequests",
      "Application.Helper.FrontendContract.Surface.Request.Runtime.Internal",
      "Application.Helper.FrontendContract.Surface.Roster",
      "Application.Helper.FrontendContract.Surface.Roster.Action",
      "Application.Helper.FrontendContract.Surface.Roster.Generated.Action",
      "Application.Helper.FrontendContract.Surface.Roster.HaskellAdapter",
      "Application.Helper.FrontendContract.Surface.SelfServiceLeave",
    ],
  },
  {
    label: "Surface.Profile.Action",
    root: "Application.Helper.FrontendContract.Surface.Profile.Action",
    expected: [
      ...sharedRequestRuntimeClosure,
      "Application.Helper.FrontendContract.Surface.Profile",
      "Application.Helper.FrontendContract.Surface.Profile.Action",
      "Application.Helper.FrontendContract.Surface.Profile.Generated.Action",
      "Application.Helper.FrontendContract.Surface.Profile.HaskellAdapter",
      "Application.Helper.FrontendContract.Surface.LeaveRequests",
      "Application.Helper.FrontendContract.Surface.SelfServiceLeave",
    ],
  },
  {
    label: "Surface.Roster.Intent",
    root: "Application.Helper.FrontendContract.Surface.Roster.Intent",
    expected: [
      ...sharedRequestRuntimeClosure,
      "Application.Helper.FrontendContract.Surface.Interaction",
      "Application.Helper.FrontendContract.Surface.Roster",
      "Application.Helper.FrontendContract.Surface.Roster.Generated.Intent",
      "Application.Helper.FrontendContract.Surface.Roster.HaskellAdapter",
      "Application.Helper.FrontendContract.Surface.Roster.Intent",
      "Application.Helper.FrontendContract.Surface.LeaveRequests",
      "Application.Helper.FrontendContract.Surface.SelfServiceLeave",
    ],
  },
];

function applicationClosure(root) {
  const seen = new Set();
  const pending = [root];
  while (pending.length > 0) {
    const name = pending.pop();
    if (seen.has(name)) continue;
    const module = modulesByName.get(name);
    if (!module) continue;
    seen.add(name);
    pending.push(...(module.imports || []));
  }
  return [...seen].filter((name) => name.startsWith("Application.")).sort();
}

function difference(left, right) {
  const rightSet = new Set(right);
  return left.filter((value) => !rightSet.has(value));
}

let failed = false;
const printModules = process.argv.includes("--print-modules");
for (const contract of closureContracts) {
  const actual = applicationClosure(contract.root);
  const expected = [...new Set(contract.expected)].sort();
  const missing = difference(expected, actual);
  const unexpected = difference(actual, expected);

  if (missing.length > 0 || unexpected.length > 0) {
    failed = true;
    console.error(`${contract.label} request closure differs: expected ${expected.length}, found ${actual.length}`);
    for (const name of missing) console.error(`  missing: ${name}`);
    for (const name of unexpected) console.error(`  unexpected: ${name}`);
    continue;
  }

  console.log(`${contract.label} request closure: ${actual.length} exact Application modules`);
  if (printModules) for (const name of actual) console.log(`  ${name}`);
}

if (failed) process.exit(1);
console.log("Surface request closure architecture check passed.");
