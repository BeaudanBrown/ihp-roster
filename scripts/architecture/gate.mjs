#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { repoRoot } from "./shared.mjs";

const factsPath = path.join(repoRoot, "output/architecture/facts.json");
if (!fs.existsSync(factsPath)) {
  console.error("Missing output/architecture/facts.json. Run architecture-facts or architecture-check-fresh first.");
  process.exit(1);
}

const facts = JSON.parse(fs.readFileSync(factsPath, "utf8"));
const handlersByModule = new Map();
for (const handler of facts.web.handlers || []) {
  if (!handlersByModule.has(handler.module)) handlersByModule.set(handler.module, []);
  handlersByModule.get(handler.module).push(handler);
}
const policyModules = new Set((facts.web.controllerPolicies || []).map((policy) => policy.module));
const actionWrapperContracts = new Set((facts.web.actionWrapperContracts || []).map((contract) => contract.name));
const mutationSpecs = new Set((facts.web.mutationSpecs || []).map((spec) => spec.name));
const errors = [];
const warnings = [];
const mutationDriftStrict = process.env.BEPIS_MUTATION_DRIFT_STRICT === "1";

for (const controller of facts.web.controllers || []) {
  const modules = new Set(controller.actions.map((action) => (facts.web.handlers || []).find((handler) => handler.action === action.name)?.module).filter(Boolean));
  if (![...modules].some((moduleName) => policyModules.has(moduleName))) {
    errors.push(`${controller.name} has no Bepis controller policy`);
  }
}

for (const handler of facts.web.handlers || []) {
  if (handler.kindSource !== "typed-wrapper") {
    errors.push(`${handler.action} is not covered by a typed Bepis action wrapper`);
    continue;
  }
  const wrapper = handler.bepisWrapper;
  if (!wrapper) {
    errors.push(`${handler.action} is missing Bepis wrapper metadata`);
    continue;
  }
  if (!actionWrapperContracts.has(wrapper.name)) {
    errors.push(`${handler.action} uses ${wrapper.name}, which is not in the typed wrapper contract registry`);
  }
  if ((wrapper.responseKinds || []).length === 0) {
    errors.push(`${handler.action} has no typed Bepis response metadata`);
  }
  if (wrapper.actionNameSource === "string-literal") {
    errors.push(`${handler.action} passes a string literal action name to ${wrapper.name}`);
  }
  if (/bepis(?:Preference|Mutation|JsonMutation)Action/.test(wrapper.name)) {
    if (!wrapper.mutationSpecName) {
      errors.push(`${handler.action} uses ${wrapper.name} without a BepisMutationSpec`);
    } else if (!mutationSpecs.has(wrapper.mutationSpecName)) {
      errors.push(`${handler.action} references unknown BepisMutationSpec ${wrapper.mutationSpecName}`);
    }

    const spec = wrapper.mutationSpec;
    if (spec) {
      const evidence = handler.mutationEffectEvidence || {};
      const warnOrFail = (message) => {
        if (mutationDriftStrict) errors.push(message);
        else warnings.push(message);
      };
      if (spec.auditPolicy === "required" && !evidence.audit) {
        warnOrFail(`${handler.action} has audit-required ${wrapper.mutationSpecName} without visible audit/version evidence`);
      }
      if (spec.realtimePolicy === "emits-invalidation" && !evidence.realtime) {
        warnOrFail(`${handler.action} has realtime-required ${wrapper.mutationSpecName} without visible LiveMutationResult/invalidation evidence`);
      }
      if (handler.mutationPipeline) {
        if (spec.auditPolicy === "required" && !(handler.mutationPipeline.auditPolicies || []).includes("required")) {
          errors.push(`${handler.action} is pipeline-backed but lacks required audit evidence`);
        }
        if (spec.realtimePolicy === "emits-invalidation" && !(handler.mutationPipeline.realtimePolicies || []).includes("emits-invalidation")) {
          errors.push(`${handler.action} is pipeline-backed but lacks realtime invalidation evidence`);
        }
      }
    }
  }
}

if (warnings.length > 0 && process.env.BEPIS_MUTATION_DRIFT_WARN === "1") {
  console.error(`Bepis mutation drift guard found ${warnings.length} warning(s):`);
  for (const warning of warnings.slice(0, 30)) console.error(`- ${warning}`);
  if (warnings.length > 30) console.error(`... ${warnings.length - 30} more`);
}

if (!mutationDriftStrict && warnings.length > 0) {
  process.stdout.write(`Bepis mutation drift guard warnings: ${warnings.length} legacy spec-backed action(s) need stronger evidence checks. Set BEPIS_MUTATION_DRIFT_WARN=1 to list them or BEPIS_MUTATION_DRIFT_STRICT=1 to fail.\n`);
}

if (errors.length > 0) {
  console.error(`Bepis architecture gate failed with ${errors.length} error(s):`);
  for (const error of errors.slice(0, 50)) console.error(`- ${error}`);
  if (errors.length > 50) console.error(`... ${errors.length - 50} more`);
  process.exit(1);
}

console.log(`Bepis architecture gate passed: ${(facts.web.controllers || []).length} controllers, ${(facts.web.handlers || []).length} typed handlers, ${(facts.web.actionWrapperContracts || []).length} wrapper contracts.`);
