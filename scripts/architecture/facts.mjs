import fs from "node:fs";
import path from "node:path";
import { fileHash, listFiles, outputDir, readText, repoRoot, writeJson } from "./shared.mjs";

function lineNumberAt(text, index) {
  return text.slice(0, index).split("\n").length;
}

function lineForMatch(text, match) {
  return lineNumberAt(text, match.index ?? 0);
}

function unique(values) {
  return [...new Set(values.filter(Boolean))].sort();
}

function snakeToPascal(value) {
  return String(value)
    .split("_")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join("");
}

function singularTableName(table) {
  if (table.endsWith("ies")) return `${table.slice(0, -3)}y`;
  if (table.endsWith("ses")) return table.slice(0, -2);
  if (table.endsWith("s")) return table.slice(0, -1);
  return table;
}

function modelNameForTable(table) {
  return snakeToPascal(singularTableName(table));
}

function classifyForeignKey(columns, referencesTable) {
  const joined = columns.join(",");
  if (referencesTable === "users" && /(^|_)(created|updated|deleted|archived|locked|requested|reviewed|approved|submitted|imported|downloaded|purged|resolved|accepted|invited|connected|disconnected|actor|read|set|decided)_by_user_id$|actor_user_id|user_id/.test(joined)) {
    if (joined === "user_id") return "identity";
    return "audit-user";
  }
  if (referencesTable === "venues" || joined.includes("venue_id")) return "tenant-scope";
  if (referencesTable.startsWith("xero_") || joined.includes("xero_")) return "integration";
  if (referencesTable.includes("passkey") || referencesTable.includes("session") || referencesTable.includes("token")) return "auth";
  return "domain";
}

function parseSchema(sql) {
  const tables = [];
  const tableRegex = /CREATE TABLE\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([\s\S]*?)\);/g;
  for (const match of sql.matchAll(tableRegex)) {
    const [, name, body] = match;
    const table = { name, model: modelNameForTable(name), columns: [], foreignKeys: [], source: { path: "Application/Schema.sql", line: lineForMatch(sql, match) } };
    for (const rawLine of body.split("\n")) {
      const line = rawLine.trim().replace(/,$/, "");
      if (!line || line.startsWith("--")) continue;
      const fk = line.match(/^FOREIGN KEY\s*\(([^)]+)\)\s+REFERENCES\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]+)\)/i);
      if (fk) {
        const columns = fk[1].split(/\s*,\s*/);
        table.foreignKeys.push({ columns, referencesTable: fk[2], referencesColumns: fk[3].split(/\s*,\s*/), kind: classifyForeignKey(columns, fk[2]) });
        continue;
      }
      if (/^(PRIMARY|UNIQUE|CONSTRAINT|CHECK)\b/i.test(line)) continue;
      const col = line.match(/^"?([A-Za-z_][A-Za-z0-9_]*)"?\s+(.+)$/);
      if (!col) continue;
      const [, columnName, rest] = col;
      const references = rest.match(/\bREFERENCES\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]+)\)/i);
      table.columns.push({ name: columnName, type: rest.split(/\s+/)[0], definition: rest });
      if (references) {
        const columns = [columnName];
        table.foreignKeys.push({ columns, referencesTable: references[1], referencesColumns: references[2].split(/\s*,\s*/), kind: classifyForeignKey(columns, references[1]) });
      }
    }
    tables.push(table);
  }
  const enums = [...sql.matchAll(/CREATE TYPE\s+([A-Za-z_][A-Za-z0-9_]*)\s+AS\s+ENUM\s*\(([^;]+)\);/g)].map((m) => ({
    name: m[1],
    values: [...m[2].matchAll(/'([^']+)'/g)].map((v) => v[1]),
    source: { path: "Application/Schema.sql", line: lineForMatch(sql, m) },
  }));
  return { tables, enums };
}

function parseControllers(typesText) {
  const controllers = [];
  const regex = /data\s+([A-Za-z0-9_]+Controller)([\s\S]*?)(?=\n\s*(?:deriving|data\s+|newtype\s+)|$)/g;
  for (const match of typesText.matchAll(regex)) {
    const [, name, body] = match;
    const actions = [];
    const actionRegex = /(?:=|\|)\s*([A-Z][A-Za-z0-9_]*Action)(?:\s*\{([^}]*)\})?/g;
    for (const actionMatch of body.matchAll(actionRegex)) {
      const fields = actionMatch[2]
        ? [...actionMatch[2].matchAll(/([a-z][A-Za-z0-9_]*)\s*::\s*([^,}]+)/g)].map((f) => ({ name: f[1], type: f[2].trim() }))
        : [];
      actions.push({ name: actionMatch[1], fields, source: { path: "Web/Types.hs", line: lineNumberAt(typesText, (match.index ?? 0) + actionMatch.index) } });
    }
    controllers.push({ name, actions, source: { path: "Web/Types.hs", line: lineForMatch(typesText, match) } });
  }
  return controllers;
}

function parseRoutes(routesText) {
  return [...routesText.matchAll(/instance\s+AutoRoute\s+([A-Za-z0-9_]+Controller)/g)].map((m) => ({ controller: m[1], source: { path: "Web/Routes.hs", line: lineForMatch(routesText, m) } }));
}

function parseFrontController(frontText) {
  return {
    imports: [...frontText.matchAll(/^import\s+(Web\.Controller\.[A-Za-z0-9_.]+)/gm)].map((m) => ({ module: m[1], source: { path: "Web/FrontController.hs", line: lineForMatch(frontText, m) } })),
    mounts: [...frontText.matchAll(/parseRoute\s+@([A-Za-z0-9_]+Controller)/g)].map((m) => ({ controller: m[1], source: { path: "Web/FrontController.hs", line: lineForMatch(frontText, m) } })),
    websocketMounts: [...frontText.matchAll(/webSocketAppWithCustomPath\s+@([A-Za-z0-9_]+)\s+"([^"]+)"/g)].map((m) => ({ app: m[1], path: m[2], source: { path: "Web/FrontController.hs", line: lineForMatch(frontText, m) } })),
  };
}

function moduleNameFromFile(relPath, text) {
  const declared = text.match(/^module\s+([A-Za-z0-9_.]+)/m);
  if (declared) return declared[1];
  return relPath.replace(/\.hs$/, "").split(path.sep).join(".");
}

function parseHaskellModules() {
  return listFiles(["Application", "Web", "Test"], (file) => file.endsWith(".hs")).map((relPath) => {
    const text = readText(relPath);
    return {
      name: moduleNameFromFile(relPath, text),
      path: relPath,
      imports: unique([...text.matchAll(/^import\s+(?:qualified\s+)?([A-Za-z][A-Za-z0-9_.]+)/gm)].map((m) => m[1])),
      source: { path: relPath, line: 1 },
    };
  });
}

function actionKind(actionName) {
  if (/FragmentAction$/.test(actionName)) return "fragment";
  if (/DialogAction$/.test(actionName)) return "dialog";
  if (/^(Create|Update|Delete|Remove|Add|Move|Sort|Toggle|Copy)/.test(actionName)) return "mutation";
  if (/PreferenceAction$|FiltersAction$/.test(actionName)) return "preference";
  if (/Webhook|Callback/.test(actionName)) return "integration";
  if (/Export|Download/.test(actionName)) return "export";
  if (/^(New|Edit)/.test(actionName)) return "form";
  return "page";
}

function parseConstructorTextMappings(text, prefix) {
  const mappings = new Map();
  const regex = new RegExp(`\\b(${prefix}[A-Za-z0-9_']+)\\s*->\\s*"([^"]+)"`, "g");
  for (const match of text.matchAll(regex)) mappings.set(match[1], match[2]);
  return mappings;
}

function extractTopLevelDefinition(text, name) {
  const match = text.match(new RegExp(`^${name}\\s+(?!::)[^=]*=`, "m"));
  if (!match) return "";
  const start = match.index ?? 0;
  const after = text.slice(start);
  const next = after.slice(match[0].length).search(/^\S/m);
  return next === -1 ? after : after.slice(0, match[0].length + next);
}

function loadBepisArchitectureContracts() {
  const relPath = "output/architecture/bepis-contracts.json";
  const absolutePath = path.join(repoRoot, relPath);
  if (!fs.existsSync(absolutePath)) return null;
  return JSON.parse(fs.readFileSync(absolutePath, "utf8"));
}

function parseBepisActionWrapperContracts(generatedContracts) {
  const generatedWrappers = generatedContracts?.actionWrappers || [];
  if (generatedWrappers.length > 0) {
    return new Map(generatedWrappers.map((contract) => [contract.name, {
      kind: contract.kind,
      responseKinds: contract.responseKinds || [],
      requiresMutationSpec: Boolean(contract.requiresMutationSpec),
      source: contract.source || { path: "output/architecture/bepis-contracts.json" },
      confidence: contract.confidence || "typed-contract",
      provenance: "generated-haskell-contract",
    }]));
  }

  const relPath = "Application/Bepis/Action.hs";
  const text = readText(relPath);
  const actionKindText = parseConstructorTextMappings(text, "Bepis");
  const responseKindText = parseConstructorTextMappings(text, "Bepis");
  const wrappers = new Map();
  for (const match of text.matchAll(/^(bepis[A-Za-z0-9_']+Action)\s*::\s*([^\n]+)/gm)) {
    const name = match[1];
    const signature = match[2];
    if (name === "bepisActionSpan") continue;
    const definition = extractTopLevelDefinition(text, name);
    const actionKindConstructor = definition.match(/actionKind\s*=\s*(Bepis[A-Za-z0-9_']+)/)?.[1];
    const responseKindConstructors = definition.match(/responseKinds\s*=\s*\[([^\]]*)\]/)?.[1]
      ?.split(",")
      .map((value) => value.trim())
      .filter(Boolean) || [];
    if (!actionKindConstructor || responseKindConstructors.length === 0) continue;
    wrappers.set(name, {
      kind: actionKindText.get(actionKindConstructor) || actionKindConstructor,
      responseKinds: responseKindConstructors.map((constructor) => responseKindText.get(constructor) || constructor),
      requiresMutationSpec: /\bBepisMutationSpec\b/.test(signature),
      source: { path: relPath, line: lineForMatch(text, match) },
      confidence: "typed-contract",
    });
  }
  return wrappers;
}

function parseBepisActionWrapper(body, relPath, handlerLine, handlerActionName, mutationSpecs, wrapperContracts) {
  const wrapperNames = [...wrapperContracts.keys()].sort((a, b) => b.length - a.length).map((name) => name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
  if (wrapperNames.length === 0) return null;
  const match = body.match(new RegExp(`\\b(${wrapperNames.join("|")})\\s+(?:"([^"]+)"|([^\\s$]+))(?:\\s+([A-Za-z][A-Za-z0-9_']*))?`));
  if (!match) return null;
  const wrapper = wrapperContracts.get(match[1]);
  if (!wrapper) return null;
  const declaredActionName = match[2] || handlerActionName;
  const actionNameSource = match[2] ? "string-literal" : "typed-action-value";
  const mutationSpecName = wrapper.requiresMutationSpec ? match[4] : undefined;
  return {
    name: match[1],
    declaredActionName,
    actionNameSource,
    kind: wrapper.kind,
    responseKinds: wrapper.responseKinds,
    mutationSpecName,
    mutationSpec: mutationSpecName ? mutationSpecs.get(mutationSpecName) : undefined,
    source: { path: relPath, line: handlerLine + lineNumberAt(body, match.index ?? 0) - 1 },
    contractSource: wrapper.source,
    contractConfidence: wrapper.confidence,
  };
}

function parseBepisControllerPolicy(text, relPath) {
  const match = text.match(/\bbeforeAction\s*=\s*bepisBeforeAction\s+(Bepis[A-Za-z0-9_]+Controller)\b/);
  if (!match) return null;
  return { policy: match[1], source: { path: relPath, line: lineForMatch(text, match) }, confidence: "typed-wrapper" };
}

function extractActionBody(text, matchIndex, indent) {
  const after = text.slice(matchIndex);
  const lines = after.split("\n");
  const bodyLines = [lines[0]];
  const actionStart = new RegExp(`^\\s{0,${Math.max(0, indent)}}action\\s+(?:[a-z][A-Za-z0-9_']*@)?[A-Z][A-Za-z0-9_]*Action\\b`);
  for (let i = 1; i < lines.length; i += 1) {
    const line = lines[i];
    if (actionStart.test(line)) break;
    if (/^[ \t]*instance\s+Controller\b/.test(line)) break;
    bodyLines.push(line);
  }
  return bodyLines.join("\n");
}

const ignoredCallWords = new Set(["if", "then", "else", "do", "let", "in", "case", "of", "where", "pure", "Just", "Nothing", "Left", "Right", "True", "False"]);

function inferActionDetails(body, tableModels) {
  const calls = unique([...body.matchAll(/\b([a-z][A-Za-z0-9_']*)\b(?=\s*(?:\(|@|\{|\"|[a-zA-Z0-9_#]))/g)].map((m) => m[1]))
    .filter((name) => !ignoredCallWords.has(name))
    .slice(0, 80);
  const renderCalls = calls.filter((name) => /^(render|respondWith|serve|redirect|json|html)/.test(name));
  const authScopeCalls = calls.filter((name) => /ensure|authorize|require|currentVenue|currentUser|permission|scope/i.test(name));
  const realtimeCalls = calls.filter((name) => /live|fragment|surface|broadcast|invalidate|websocket|typedLive/i.test(name));
  const tableRefs = [];
  for (const [model, table] of tableModels) {
    const modelRegex = new RegExp(`\\b${model}\\b|@${model}\\b`, "g");
    if (modelRegex.test(body)) tableRefs.push(table);
  }
  const dataAccess = unique(calls.filter((name) => /^(query|fetch|fetchOne|fetchBy|get|create|update|delete|build|newRecord|find|filterWhere|orderBy|collection)/.test(name)));
  const responseKinds = unique([
    /redirectTo|redirectToPath/.test(body) ? "redirect" : "",
    /renderHtml|render\s/.test(body) ? "html" : "",
    /respondWith|serveTypedLiveFragment|Fragment/.test(body) ? "fragment-or-htmx" : "",
    /json|renderJson/.test(body) ? "json" : "",
  ]);
  return { calls, renderCalls, authScopeCalls, realtimeCalls, tableRefs: unique(tableRefs), dataAccess, responseKinds };
}

function parseBepisMutationPolicyTextMappings(generatedContracts) {
  const generatedPolicies = generatedContracts?.mutationPolicies || [];
  if (generatedPolicies.length > 0) {
    return new Map(generatedPolicies.map((policy) => [policy.constructor, policy.label]));
  }
  return parseConstructorTextMappings(readText("Application/Bepis/Mutation.hs"), "Bepis");
}

function parseBepisMutationSpecs(files, policyText) {
  const specs = new Map();
  for (const relPath of files) {
    const text = readText(relPath);
    const regex = /^([a-z][A-Za-z0-9_']*)\s*::\s*BepisMutationSpec[\s\S]*?^\1\s*=\s*BepisMutationSpec\s*\{([\s\S]*?)^\s*\}/gm;
    for (const match of text.matchAll(regex)) {
      const fields = match[2];
      const fieldValue = (name) => fields.match(new RegExp(`${name}\\s*=\\s*([A-Za-z][A-Za-z0-9_']*)`))?.[1];
      specs.set(match[1], {
        name: match[1],
        auditPolicy: policyText.get(fieldValue("auditPolicy")) || fieldValue("auditPolicy"),
        realtimePolicy: policyText.get(fieldValue("realtimePolicy")) || fieldValue("realtimePolicy"),
        scopePolicy: policyText.get(fieldValue("scopePolicy")) || fieldValue("scopePolicy"),
        source: { path: relPath, line: lineForMatch(text, match) },
        confidence: "typed-wrapper",
      });
    }
  }
  return specs;
}

function parseBepisMutationPipeline(body, relPath, handlerLine, generatedContracts) {
  if (!/\bnewMutation\b/.test(body) || !/\brunBepisMutationPipeline\b/.test(body)) return null;
  const componentContracts = generatedContracts?.mutationComponents || [];
  const componentNames = componentContracts.map((component) => component.name);
  const usedComponents = componentNames.filter((name) => new RegExp(`\\b${name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`).test(body));
  const labelsFor = (name) => [...body.matchAll(new RegExp(`\\b${name}\\s+"([^"]+)"`, "g"))].map((match) => match[1]);
  const scopePolicies = unique([
    /\bscopedToCurrentUser\b/.test(body) ? "current-user" : "",
    /\bscopedToCurrentVenue\b/.test(body) ? "current-venue" : "",
    /\bscopedToRosterWeek\b/.test(body) ? "venue-roster-week" : "",
    /\bscopedToSupport\b/.test(body) ? "support" : "",
  ]);
  const auditLabels = labelsFor("auditedAs");
  const realtimeLabels = labelsFor("fromLiveMutationResult");
  const noRealtimeLabels = labelsFor("withNoRealtimeInvalidation");
  const responseKinds = unique([
    /\brespondsWithFragments\b/.test(body) ? "htmx-fragment" : "",
    /\brespondsWithRedirect\b/.test(body) ? "redirect" : "",
    /\brespondsWithJson\b/.test(body) ? "json" : "",
  ]);
  const newMutationMatch = body.match(/\bnewMutation\b/);
  return {
    source: { path: relPath, line: handlerLine + lineNumberAt(body, newMutationMatch?.index ?? 0) - 1 },
    confidence: "typed-component-pipeline",
    provenance: "generated-haskell-contract",
    components: usedComponents,
    scopePolicies,
    auditPolicies: auditLabels.length > 0 ? ["required"] : [],
    auditLabels,
    realtimePolicies: unique([
      realtimeLabels.length > 0 ? "emits-invalidation" : "",
      noRealtimeLabels.length > 0 ? "none" : "",
    ]),
    realtimeLabels: [...realtimeLabels, ...noRealtimeLabels],
    responseKinds,
  };
}

function parseHandlers(controllerFiles, tableModels, mutationSpecs, wrapperContracts, generatedContracts) {
  const handlers = [];
  for (const relPath of controllerFiles) {
    const text = readText(relPath);
    const moduleName = moduleNameFromFile(relPath, text);
    for (const m of text.matchAll(/^([ \t]*)action\s+(?:[a-z][A-Za-z0-9_']*@)?([A-Z][A-Za-z0-9_]*Action)\b/gm)) {
      const indent = m[1].length;
      const line = lineForMatch(text, m);
      const body = extractActionBody(text, m.index ?? 0, indent);
      const inferred = inferActionDetails(body, tableModels);
      const bepisWrapper = parseBepisActionWrapper(body, relPath, line, m[2], mutationSpecs, wrapperContracts);
      const mutationPipeline = parseBepisMutationPipeline(body, relPath, line, generatedContracts);
      handlers.push({
        action: m[2],
        module: moduleName,
        path: relPath,
        line,
        kind: bepisWrapper?.kind || actionKind(m[2]),
        kindSource: bepisWrapper ? "typed-wrapper" : "naming-fallback",
        confidence: bepisWrapper ? "typed-wrapper" : "heuristic-static-scan",
        bepisWrapper,
        mutationPipeline,
        bodyLineCount: body.split("\n").length,
        ...inferred,
        responseKinds: unique([...(mutationPipeline?.responseKinds || []), ...(bepisWrapper?.responseKinds || []), ...(inferred.responseKinds || [])]),
      });
    }
  }
  return handlers;
}

function parseControllerPolicies(controllerFiles) {
  return controllerFiles.map((relPath) => {
    const text = readText(relPath);
    return {
      module: moduleNameFromFile(relPath, text),
      path: relPath,
      policy: parseBepisControllerPolicy(text, relPath),
    };
  }).filter((entry) => entry.policy);
}

function parseViews(viewFiles) {
  return viewFiles.map((relPath) => {
    const text = readText(relPath);
    const moduleName = moduleNameFromFile(relPath, text);
    const viewTypes = [...text.matchAll(/(?:data|newtype)\s+([A-Z][A-Za-z0-9_]*View)\b/g)].map((m) => m[1]);
    const dataBepisAttributes = unique([...text.matchAll(/data-bepis-[a-z0-9-]+/g)].map((m) => m[0]));
    return { module: moduleName, path: relPath, viewTypes, dataBepisAttributes, source: { path: relPath, line: 1 } };
  });
}

function classifyActionReference(text, index) {
  const before = text.slice(Math.max(0, index - 80), index);
  const after = text.slice(index, Math.min(text.length, index + 120));
  const context = `${before}${after}`;
  if (/pathTo\s*$/.test(before) || /pathTo\s+/.test(context)) return "path";
  if (/redirectTo\s*$/.test(before) || /redirectTo\s+/.test(context)) return "redirect";
  if (/form|method=|hx-/.test(context)) return "form-or-htmx";
  if (/render|href|link/.test(context)) return "link-or-render";
  return "reference";
}

function parseActionReferences(files, actionNames) {
  const refs = [];
  const skip = new Set(["Web/Types.hs"]);
  for (const relPath of files) {
    if (skip.has(relPath)) continue;
    const text = readText(relPath);
    for (const actionName of actionNames) {
      const regex = new RegExp(`\\b${actionName}\\b`, "g");
      for (const m of text.matchAll(regex)) {
        refs.push({ action: actionName, path: relPath, line: lineForMatch(text, m), kind: classifyActionReference(text, m.index ?? 0) });
      }
    }
  }
  return refs;
}

function parseRealtime(files) {
  const surfaces = [];
  const references = [];
  for (const relPath of files) {
    const text = readText(relPath);
    const isRealtimeFile = /Live(Update|Surface|Resource)|live-updates|lazy-surface/i.test(relPath);
    const matches = [...text.matchAll(/\b(serveTypedLiveFragment|respondWithTypedLiveSurfaceFragments|typedLiveSurfaceAffectedFragments|LiveUpdate|LiveSurface|LiveResource|webSocketAppWithCustomPath|data-bepis-lazy-surface|data-bepis-surface)\b/g)];
    if (isRealtimeFile || matches.length > 0) {
      references.push({ path: relPath, source: { path: relPath, line: 1 }, referenceCount: matches.length, mechanism: isRealtimeFile ? "realtime-module" : "realtime-reference" });
    }
    for (const m of text.matchAll(/^([a-z][A-Za-z0-9_]*LiveSurfaceDefinition)\s*::/gm)) {
      surfaces.push({ name: m[1], path: relPath, line: lineForMatch(text, m), mechanism: "typed-live-surface-definition" });
    }
  }
  return { surfaces, references };
}

function parseFrontendContracts() {
  const generatedFiles = listFiles(["frontend/ts/generated"], (file) => file.endsWith(".ts"));
  const tsFiles = listFiles(["frontend/ts"], (file) => file.endsWith(".ts"));
  const consumers = [];
  for (const relPath of tsFiles) {
    const text = readText(relPath);
    if (relPath.includes("/generated/")) continue;
    const importsGenerated = /from\s+["'](?:\.\.\/)*generated\/contracts["']|from\s+["']\.\/generated\/contracts["']/.test(text);
    if (importsGenerated) {
      consumers.push({ path: relPath, imports: [...text.matchAll(/import\s+(?:type\s+)?\{([^}]+)\}\s+from\s+["'][^"']*generated\/contracts["']/g)].flatMap((m) => m[1].split(",").map((x) => x.trim().replace(/^type\s+/, ""))).filter(Boolean) });
    }
  }
  const sources = ["Application/Helper/Frontend/Contracts.hs", "Application/Helper/Frontend/ContractGroup.hs", "Application/Script/GenerateFrontendContracts.hs"].filter((file) => fs.existsSync(path.join(repoRoot, file)));
  const generated = generatedFiles.map((relPath) => {
    const text = readText(relPath);
    return {
      path: relPath,
      exports: unique([...text.matchAll(/^export\s+(?:const|type|interface|function)\s+([A-Za-z0-9_]+)/gm)].map((m) => m[1])),
      dataAttributes: unique([...text.matchAll(/data-bepis-[a-z0-9-]+/g)].map((m) => m[0])),
    };
  });
  return { sources, generated, consumers };
}

const sourceFiles = ["Application/Schema.sql", "Web/Types.hs", "Web/Routes.hs", "Web/FrontController.hs"];
const controllerFiles = listFiles(["Web/Controller"], (file) => file.endsWith(".hs"));
const viewFiles = listFiles(["Web/View"], (file) => file.endsWith(".hs"));
const moduleFiles = listFiles(["Application", "Web", "Test"], (file) => file.endsWith(".hs"));
const frontendFiles = listFiles(["frontend/ts", "static"], (file) => /\.(ts|js|hs|tsx|jsx)$/.test(file));
const schema = parseSchema(readText("Application/Schema.sql"));
const controllers = parseControllers(readText("Web/Types.hs"));
const actionNames = controllers.flatMap((controller) => controller.actions.map((action) => action.name));
const tableModels = new Map(schema.tables.map((table) => [table.model, table.name]));
const allReferenceFiles = unique([...moduleFiles, ...viewFiles, ...frontendFiles]);
const bepisArchitectureContracts = loadBepisArchitectureContracts();
const bepisMutationPolicyText = parseBepisMutationPolicyTextMappings(bepisArchitectureContracts);
const bepisMutationSpecs = parseBepisMutationSpecs(moduleFiles, bepisMutationPolicyText);
const bepisActionWrapperContracts = parseBepisActionWrapperContracts(bepisArchitectureContracts);
const facts = {
  version: 2,
  generatedBy: "scripts/architecture/facts.mjs",
  model: "source-scanned entities/relationships with generated typed Bepis contracts, provenance, and heuristic confidence",
  sources: Object.fromEntries([...sourceFiles, ...controllerFiles, ...viewFiles, ...moduleFiles, ...frontendFiles].sort().map((file) => [file, fileHash(file)])),
  schema,
  web: {
    controllers,
    routes: parseRoutes(readText("Web/Routes.hs")),
    frontController: parseFrontController(readText("Web/FrontController.hs")),
    handlers: parseHandlers(controllerFiles, tableModels, bepisMutationSpecs, bepisActionWrapperContracts, bepisArchitectureContracts),
    controllerPolicies: parseControllerPolicies(controllerFiles),
    actionWrapperContracts: [...bepisActionWrapperContracts.entries()].map(([name, contract]) => ({ name, ...contract })),
    bepisArchitectureContracts: bepisArchitectureContracts ? {
      version: bepisArchitectureContracts.version,
      generatedBy: bepisArchitectureContracts.generatedBy,
      provenance: bepisArchitectureContracts.provenance,
      source: { path: "output/architecture/bepis-contracts.json" },
      mutationComponentCount: bepisArchitectureContracts.mutationComponents?.length || 0,
    } : undefined,
    mutationSpecs: [...bepisMutationSpecs.values()],
    views: parseViews(viewFiles),
    actionReferences: parseActionReferences(allReferenceFiles, actionNames),
  },
  modules: parseHaskellModules(),
  realtime: parseRealtime(allReferenceFiles),
  frontend: {
    contracts: parseFrontendContracts(),
  },
};

fs.mkdirSync(outputDir, { recursive: true });
writeJson("output/architecture/facts.json", facts);
console.log("Generated output/architecture/facts.json");
