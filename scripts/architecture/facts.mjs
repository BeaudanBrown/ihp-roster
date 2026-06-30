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

const bepisActionWrappers = {
  bepisPageAction: { kind: "page", responseKinds: ["html", "redirect"] },
  bepisFragmentAction: { kind: "fragment", responseKinds: ["htmx-fragment"] },
  bepisDialogAction: { kind: "dialog", responseKinds: ["dialog", "htmx-fragment"] },
  bepisMutationAction: { kind: "mutation", responseKinds: ["redirect", "htmx-fragment"] },
};

function parseBepisActionWrapper(body, relPath, handlerLine, mutationSpecs) {
  const match = body.match(/\b(bepis(?:Page|Fragment|Dialog|Mutation)Action)\s+"([^"]+)"(?:\s+([A-Za-z][A-Za-z0-9_']*))?/);
  if (!match) return null;
  const wrapper = bepisActionWrappers[match[1]];
  if (!wrapper) return null;
  return {
    name: match[1],
    declaredActionName: match[2],
    kind: wrapper.kind,
    responseKinds: wrapper.responseKinds,
    mutationSpecName: match[1] === "bepisMutationAction" ? match[3] : undefined,
    mutationSpec: match[1] === "bepisMutationAction" && match[3] ? mutationSpecs.get(match[3]) : undefined,
    source: { path: relPath, line: handlerLine + lineNumberAt(body, match.index ?? 0) - 1 },
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
  const actionStart = new RegExp(`^\\s{0,${Math.max(0, indent)}}action\\s+[A-Z][A-Za-z0-9_]*Action\\b`);
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

function constructorPolicyText(value) {
  const mapping = {
    BepisAuditNotRequired: "not-required",
    BepisAuditRequired: "required",
    BepisAuditForbidden: "forbidden",
    BepisRealtimeNotApplicable: "not-applicable",
    BepisNoRealtimeInvalidation: "none",
    BepisEmitsRealtimeInvalidation: "emits-invalidation",
    BepisRefetchesLiveFragment: "refetches-live-fragment",
    BepisNoScopePolicy: "none",
    BepisCurrentUserScope: "current-user",
    BepisCurrentVenueScope: "current-venue",
    BepisVenueRosterWeekScope: "venue-roster-week",
    BepisVenueRosterGroupScope: "venue-roster-group",
    BepisSupportScope: "support",
  };
  return mapping[value] || value;
}

function parseBepisMutationSpecs(files) {
  const specs = new Map();
  for (const relPath of files) {
    const text = readText(relPath);
    const regex = /^([a-z][A-Za-z0-9_']*)\s*::\s*BepisMutationSpec[\s\S]*?^\1\s*=\s*BepisMutationSpec\s*\{([\s\S]*?)^\s*\}/gm;
    for (const match of text.matchAll(regex)) {
      const fields = match[2];
      const fieldValue = (name) => fields.match(new RegExp(`${name}\\s*=\\s*([A-Za-z][A-Za-z0-9_']*)`))?.[1];
      specs.set(match[1], {
        name: match[1],
        auditPolicy: constructorPolicyText(fieldValue("auditPolicy")),
        realtimePolicy: constructorPolicyText(fieldValue("realtimePolicy")),
        scopePolicy: constructorPolicyText(fieldValue("scopePolicy")),
        source: { path: relPath, line: lineForMatch(text, match) },
        confidence: "typed-wrapper",
      });
    }
  }
  return specs;
}

function parseHandlers(controllerFiles, tableModels, mutationSpecs) {
  const handlers = [];
  for (const relPath of controllerFiles) {
    const text = readText(relPath);
    const moduleName = moduleNameFromFile(relPath, text);
    for (const m of text.matchAll(/^([ \t]*)action\s+([A-Z][A-Za-z0-9_]*Action)\b/gm)) {
      const indent = m[1].length;
      const line = lineForMatch(text, m);
      const body = extractActionBody(text, m.index ?? 0, indent);
      const inferred = inferActionDetails(body, tableModels);
      const bepisWrapper = parseBepisActionWrapper(body, relPath, line, mutationSpecs);
      handlers.push({
        action: m[2],
        module: moduleName,
        path: relPath,
        line,
        kind: bepisWrapper?.kind || actionKind(m[2]),
        kindSource: bepisWrapper ? "typed-wrapper" : "naming-fallback",
        confidence: bepisWrapper ? "typed-wrapper" : "heuristic-static-scan",
        bepisWrapper,
        bodyLineCount: body.split("\n").length,
        ...inferred,
        responseKinds: unique([...(bepisWrapper?.responseKinds || []), ...(inferred.responseKinds || [])]),
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
const bepisMutationSpecs = parseBepisMutationSpecs(moduleFiles);
const facts = {
  version: 2,
  generatedBy: "scripts/architecture/facts.mjs",
  model: "source-scanned entities/relationships with provenance and heuristic confidence",
  sources: Object.fromEntries([...sourceFiles, ...controllerFiles, ...viewFiles, ...moduleFiles, ...frontendFiles].sort().map((file) => [file, fileHash(file)])),
  schema,
  web: {
    controllers,
    routes: parseRoutes(readText("Web/Routes.hs")),
    frontController: parseFrontController(readText("Web/FrontController.hs")),
    handlers: parseHandlers(controllerFiles, tableModels, bepisMutationSpecs),
    controllerPolicies: parseControllerPolicies(controllerFiles),
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
