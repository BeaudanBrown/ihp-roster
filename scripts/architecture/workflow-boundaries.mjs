import { readText } from "./shared.mjs";
import { stripHaskellComments } from "./wiring-source.mjs";

// Adopted modules only. This is dependency policy, not a runtime/effect registry.
export const workflowRoles = [
  ["Web.Exports.WorkbookConfigurations", "workflow", "Exports"],
  ["Web.RosterWeeks.ShiftWorkflow", "workflow", "Roster"],
  ["Web.Exports.Responses", "response", "Exports"],
  ["Web.RosterWeeks.Responses", "response", "Roster"],
  ["Web.Exports.Mutations", "mutation", "Exports"],
  ["Web.RosterWeeks.Mutations", "mutation", "Roster"],
  ["Web.Billing.Mutations", "mutation", "Billing"],
  ["Web.Timesheets.EntryWorkflow", "workflow", "Timesheets"],
  ["Web.Timesheets.Responses", "response", "Timesheets"],
  ["Web.Timesheets.Mutations", "mutation", "Timesheets"],
  ["Application.Helper.Export.PayrollWorkbookConfiguration", "application", "Exports"],
  ["Application.Billing.Checkout", "application", "Billing"],
];

export const workflowImportExceptions = [{
  name: "roster-completion-result-type",
  module: "Web.RosterWeeks.Responses",
  dependency: "Web.RosterWeeks.Mutations",
  onlyTypes: ["RosterSlotMutationResult"],
  owner: "Roster",
  reason: "Response-only move/duplicate/assignment/delete consumers share the committed mutation result type; no mutation functions are imported.",
}];

// Import declarations, not a Haskell call graph. Ignore comments (including
// SOURCE pragmas), retain line numbers, and handle qualified/package imports.
export function workflowImports(source, sourcePath) {
  const active = stripHaskellComments(source);
  const imports = [];
  const pattern = /^[ \t]*import\s+(?:(?:safe|qualified)\s+|"[^"\n]+"\s+)*([A-Z][\w']*(?:\.[A-Z][\w']*)*)(?:\s+qualified)?(?:\s+as\s+[A-Z][\w'.]*)?/gm;
  for (const match of active.matchAll(pattern)) {
    const tail = active.slice(match.index + match[0].length).trimStart();
    const explicit = /^\(([^()]*)\)/.exec(tail);
    const names = explicit ? explicit[1].split(",").map((name) => name.trim()).filter(Boolean) : null;
    imports.push({ dependency: match[1], names, source: { path: sourcePath, line: active.slice(0, match.index).split("\n").length } });
  }
  return imports;
}

function forbiddenImport(role, dependency, roles) {
  const targetRole = roles.get(dependency);
  if (role === "application" && dependency.startsWith("Web.")) return "application-web-dependency";
  if (role === "mutation" && (dependency.startsWith("Web.View.") || targetRole === "workflow" || targetRole === "response")) return "mutation-presentation-dependency";
  if (role === "workflow" && targetRole === "response") return "workflow-response-dependency";
  if (role === "response" && targetRole === "mutation") return "response-mutation-dependency";
  if (["workflow", "response"].includes(role) && [
    "Web.SurfaceInvalidation",
    "Application.Helper.LiveUpdate.DurablePublisher",
    "Application.Helper.LiveUpdate.Runtime",
  ].includes(dependency)) return "request-passive-publisher-dependency";
  return null;
}

export function inspectWorkflowBoundaries(loadSource = readText, adopted = workflowRoles, exceptions = workflowImportExceptions) {
  const modules = [];
  const violations = [];
  const roles = new Map();
  const used = new Set();
  const names = new Set();
  const selectors = new Set();
  const policySource = { path: "scripts/architecture/workflow-boundaries.mjs", line: 1 };
  const report = (rule, owner, source, message) => violations.push({ rule, owner, source, message });
  for (const [module, role, owner] of adopted) {
    if (!module || !["workflow", "response", "mutation", "application"].includes(role) || !owner?.trim() || roles.has(module)) {
      report("workflow-policy", owner || "Architecture", policySource, `Invalid or duplicate adopted role: ${module}`);
    }
    roles.set(module, role);
  }
  const validExceptions = exceptions.filter((exception) => {
    const key = `${exception.module}:${exception.dependency}`;
    const valid = exception.name?.trim() && exception.owner?.trim() && exception.reason?.trim()
      && roles.get(exception.module) === "response" && roles.get(exception.dependency) === "mutation"
      && Array.isArray(exception.onlyTypes) && exception.onlyTypes.length > 0
      && exception.onlyTypes.every((name) => /^[A-Z][\w']*$/.test(name))
      && new Set(exception.onlyTypes).size === exception.onlyTypes.length
      && !names.has(exception.name) && !selectors.has(key);
    names.add(exception.name);
    selectors.add(key);
    if (!valid) report("workflow-exception", exception.owner || "Architecture", policySource, `Invalid or duplicate type-only exception: ${exception.name || "unnamed"}`);
    return valid;
  });
  for (const [module, role, owner] of adopted) {
    const sourcePath = `${module.replaceAll(".", "/")}.hs`;
    let source;
    try { source = loadSource(sourcePath); } catch {
      report("workflow-source", owner, { path: sourcePath, line: 1 }, `Missing adopted ${role} module ${module}`);
      continue;
    }
    if (!new RegExp(`^module\\s+${module.replaceAll(".", "\\.")}\\b`, "m").test(stripHaskellComments(source))) {
      report("workflow-source", owner, { path: sourcePath, line: 1 }, `Expected module declaration ${module}`);
    }
    const imports = workflowImports(source, sourcePath);
    modules.push({ module, role, owner, source: { path: sourcePath, line: 1 }, imports });
    for (const imported of imports) {
      const rule = forbiddenImport(role, imported.dependency, roles);
      if (!rule) continue;
      const exception = validExceptions.find((entry) => entry.module === module && entry.dependency === imported.dependency
        && imported.names?.length > 0
        && imported.names.every((name) => /^type\s+/.test(name) && entry.onlyTypes.includes(name.replace(/^type\s+/, "")))
        && entry.onlyTypes.every((name) => imported.names.some((selector) => selector.replace(/^type\s+/, "") === name)));
      if (exception) { used.add(exception.name); continue; }
      report(rule, owner, imported.source, `${module} (${role}) must not import ${imported.dependency}; keep mutation, response and passive publication ownership separate`);
    }
  }
  for (const exception of validExceptions) {
    if (!used.has(exception.name)) report("workflow-exception", exception.owner, policySource, `Stale type-only exception: ${exception.name}`);
  }
  return { modules, exceptions: validExceptions.filter((exception) => used.has(exception.name)), violations };
}

export function workflowViolationMessage(violation) {
  return `${violation.source.path}:${violation.source.line} [${violation.rule}; owner=${violation.owner}] ${violation.message}`;
}
