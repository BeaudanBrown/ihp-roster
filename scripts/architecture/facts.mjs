import fs from "node:fs";
import path from "node:path";
import { fileHash, listFiles, outputDir, readText, repoRoot, writeJson } from "./shared.mjs";
import { wiringRegistryPolicy } from "./wiring-policy.mjs";
import { parseControllerMounts, parseControllerRoutes, parseFrontendLayoutScripts } from "./wiring-source.mjs";

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

function parseFrontController(frontText) {
  return {
    imports: [...frontText.matchAll(/^import\s+(Web\.Controller\.[A-Za-z0-9_.]+)/gm)].map((m) => ({ module: m[1], source: { path: "Web/FrontController.hs", line: lineForMatch(frontText, m) } })),
    mounts: parseControllerMounts(frontText),
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

function parseRunBepis(body, relPath, handlerLine, handlerActionName, generatedContracts) {
  const match = body.match(/\brunBepis\s+(?:"([^"]+)"|([^\s$]+))\s+(Bepis[A-Za-z0-9_']+)/);
  if (!match) return null;
  const operationKindConstructor = match[3];
  const operationKinds = generatedContracts?.operationKinds || generatedContracts?.actionKinds || [];
  const responseKinds = generatedContracts?.responseKinds || [];
  const kindLabel = operationKinds.find((entry) => entry.constructor === operationKindConstructor)?.label || actionKind(handlerActionName);
  return {
    name: "runBepis",
    declaredActionName: match[1] || handlerActionName,
    actionNameSource: match[1] ? "string-literal" : "typed-action-value",
    operationKindConstructor,
    kind: kindLabel,
    responseKinds: responseKinds.map((entry) => entry.label).filter(Boolean),
    source: { path: relPath, line: handlerLine + lineNumberAt(body, match.index ?? 0) - 1 },
    contractSource: { path: "output/architecture/bepis-contracts.json" },
    contractConfidence: "typed-contract",
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

function extractTopLevelFunctionBodies(files) {
  const functions = new Map();
  for (const relPath of files) {
    const text = readText(relPath);
    const matches = [...text.matchAll(/^([a-z][A-Za-z0-9_']*)\s*(?:::|[^=\n]*=)/gm)];
    for (let index = 0; index < matches.length; index += 1) {
      const match = matches[index];
      const name = match[1];
      if (match[0].includes("::")) continue;
      const start = match.index ?? 0;
      const end = matches[index + 1]?.index ?? text.length;
      functions.set(name, { body: text.slice(start, end), source: { path: relPath, line: lineForMatch(text, match) } });
    }
  }
  return functions;
}

function parseHandlers(controllerFiles, tableModels, generatedContracts) {
  const handlers = [];
  for (const relPath of controllerFiles) {
    const text = readText(relPath);
    const moduleName = moduleNameFromFile(relPath, text);
    for (const m of text.matchAll(/^([ \t]*)action\s+(?:[a-z][A-Za-z0-9_']*@)?([A-Z][A-Za-z0-9_]*Action)\b/gm)) {
      const indent = m[1].length;
      const line = lineForMatch(text, m);
      const body = extractActionBody(text, m.index ?? 0, indent);
      const inferred = inferActionDetails(body, tableModels);
      const bepisWrapper = parseRunBepis(body, relPath, line, m[2], generatedContracts);
      handlers.push({
        action: m[2],
        module: moduleName,
        path: relPath,
        line,
        kind: bepisWrapper?.kind || actionKind(m[2]),
        kindSource: bepisWrapper ? "typed-runner" : "naming-fallback",
        confidence: bepisWrapper ? "typed-runner" : "heuristic-static-scan",
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

function parseFrontendWiring() {
  const entrypoints = listFiles(["frontend/ts"], (file) =>
    path.dirname(path.relative(repoRoot, file)) === "frontend/ts"
      && /^app.*\.ts$/.test(path.basename(file))
  ).map((relPath) => ({
    path: relPath,
    outputAsset: `/${path.basename(relPath, ".ts")}.js`,
    source: { path: relPath, line: 1 },
  }));
  const layoutPath = "Web/View/Layout.hs";
  const layoutScripts = parseFrontendLayoutScripts(readText(layoutPath), layoutPath);
  return { entrypoints, layoutScripts };
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
  const sources = [
    "Application/Architecture/Contracts.hs",
    "Application/Helper/FrontendContract/Surface/Registry.hs",
    "Application/Helper/FrontendContract/Surface/Reflect.hs",
    "Application/Helper/FrontendContract/Surface/Contracts.hs",
    "Application/Helper/FrontendContract/Surface/Architecture.hs",
    "Application/Helper/FrontendContract/Contracts.hs",
    "Application/Helper/FrontendContract/TypeScript.hs",
    "Application/Script/GenerateFrontendContracts.hs",
  ].filter((file) => fs.existsSync(path.join(repoRoot, file)));
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

const sourceFiles = ["Application/Schema.sql", "Web/Types.hs", "Web/Routes.hs", "Web/FrontController.hs", "Web/View/Layout.hs"];
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
const facts = {
  version: 3,
  generatedBy: "scripts/architecture/facts.mjs",
  model: "source-scanned entities/relationships with generated typed Bepis contracts, provenance, and heuristic confidence",
  sources: Object.fromEntries([...sourceFiles, ...controllerFiles, ...viewFiles, ...moduleFiles, ...frontendFiles].sort().map((file) => [file, fileHash(file)])),
  schema,
  web: {
    controllers,
    routes: parseControllerRoutes(readText("Web/Routes.hs")),
    frontController: parseFrontController(readText("Web/FrontController.hs")),
    handlers: parseHandlers(controllerFiles, tableModels, bepisArchitectureContracts),
    controllerPolicies: parseControllerPolicies(controllerFiles),
    bepisArchitectureContracts: bepisArchitectureContracts ? {
      version: bepisArchitectureContracts.version,
      generatedBy: bepisArchitectureContracts.generatedBy,
      provenance: bepisArchitectureContracts.provenance,
      source: { path: "output/architecture/bepis-contracts.json" },
      factKindCount: bepisArchitectureContracts.factKinds?.length || 0,
    } : undefined,
    views: parseViews(viewFiles),
    actionReferences: parseActionReferences(allReferenceFiles, actionNames),
  },
  modules: parseHaskellModules(),
  realtime: parseRealtime(allReferenceFiles),
  wiringRegistryPolicy,
  frontend: {
    ...parseFrontendWiring(),
    contracts: {
      ...parseFrontendContracts(),
      reflectedSurfaceContracts: bepisArchitectureContracts?.frontendSurfaceContracts,
    },
  },
};

fs.mkdirSync(outputDir, { recursive: true });
writeJson("output/architecture/facts.json", facts);
console.log("Generated output/architecture/facts.json");
