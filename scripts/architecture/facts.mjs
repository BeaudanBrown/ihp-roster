import fs from "node:fs";
import path from "node:path";
import { fileHash, listFiles, outputDir, readText, repoRoot, writeJson } from "./shared.mjs";

function parseSchema(sql) {
  const tables = [];
  const tableByName = new Map();
  const tableRegex = /CREATE TABLE\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([\s\S]*?)\);/g;
  for (const match of sql.matchAll(tableRegex)) {
    const [, name, body] = match;
    const table = { name, columns: [], foreignKeys: [], source: "Application/Schema.sql" };
    for (const rawLine of body.split("\n")) {
      const line = rawLine.trim().replace(/,$/, "");
      if (!line || line.startsWith("--")) continue;
      const fk = line.match(/^FOREIGN KEY\s*\(([^)]+)\)\s+REFERENCES\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]+)\)/i);
      if (fk) {
        table.foreignKeys.push({ columns: fk[1].split(/\s*,\s*/), referencesTable: fk[2], referencesColumns: fk[3].split(/\s*,\s*/) });
        continue;
      }
      if (/^(PRIMARY|UNIQUE|CONSTRAINT|CHECK)\b/i.test(line)) continue;
      const col = line.match(/^"?([A-Za-z_][A-Za-z0-9_]*)"?\s+(.+)$/);
      if (!col) continue;
      const [, columnName, rest] = col;
      const references = rest.match(/\bREFERENCES\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]+)\)/i);
      table.columns.push({ name: columnName, type: rest.split(/\s+/)[0], definition: rest });
      if (references) {
        table.foreignKeys.push({ columns: [columnName], referencesTable: references[1], referencesColumns: references[2].split(/\s*,\s*/) });
      }
    }
    tables.push(table);
    tableByName.set(name, table);
  }
  const enums = [...sql.matchAll(/CREATE TYPE\s+([A-Za-z_][A-Za-z0-9_]*)\s+AS\s+ENUM\s*\(([^;]+)\);/g)].map((m) => ({
    name: m[1],
    values: [...m[2].matchAll(/'([^']+)'/g)].map((v) => v[1]),
    source: "Application/Schema.sql",
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
      actions.push({ name: actionMatch[1], fields });
    }
    controllers.push({ name, actions, source: "Web/Types.hs" });
  }
  return controllers;
}

function parseRoutes(routesText) {
  return [...routesText.matchAll(/instance\s+AutoRoute\s+([A-Za-z0-9_]+Controller)/g)].map((m) => ({ controller: m[1], source: "Web/Routes.hs" }));
}

function parseFrontController(frontText) {
  return {
    imports: [...frontText.matchAll(/^import\s+(Web\.Controller\.[A-Za-z0-9_.]+)/gm)].map((m) => ({ module: m[1], source: "Web/FrontController.hs" })),
    mounts: [...frontText.matchAll(/parseRoute\s+@([A-Za-z0-9_]+Controller)/g)].map((m) => ({ controller: m[1], source: "Web/FrontController.hs" })),
    websocketMounts: [...frontText.matchAll(/webSocketAppWithCustomPath\s+@([A-Za-z0-9_]+)\s+"([^"]+)"/g)].map((m) => ({ app: m[1], path: m[2], source: "Web/FrontController.hs" })),
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
      imports: [...text.matchAll(/^import\s+(?:qualified\s+)?([A-Za-z][A-Za-z0-9_.]+)/gm)].map((m) => m[1]).sort(),
    };
  });
}

function parseHandlers(controllerFiles) {
  const handlers = [];
  for (const relPath of controllerFiles) {
    const text = readText(relPath);
    const moduleName = moduleNameFromFile(relPath, text);
    for (const m of text.matchAll(/^\s*action\s+([A-Z][A-Za-z0-9_]*Action)\b/gm)) {
      handlers.push({ action: m[1], module: moduleName, path: relPath });
    }
  }
  return handlers;
}

function parseViews(viewFiles) {
  return viewFiles.map((relPath) => {
    const text = readText(relPath);
    const moduleName = moduleNameFromFile(relPath, text);
    const viewTypes = [...text.matchAll(/(?:data|newtype)\s+([A-Z][A-Za-z0-9_]*View)\b/g)].map((m) => m[1]);
    return { module: moduleName, path: relPath, viewTypes };
  });
}

const sourceFiles = ["Application/Schema.sql", "Web/Types.hs", "Web/Routes.hs", "Web/FrontController.hs"];
const controllerFiles = listFiles(["Web/Controller"], (file) => file.endsWith(".hs"));
const viewFiles = listFiles(["Web/View"], (file) => file.endsWith(".hs"));
const moduleFiles = listFiles(["Application", "Web", "Test"], (file) => file.endsWith(".hs"));
const facts = {
  version: 1,
  generatedBy: "scripts/architecture/facts.mjs",
  sources: Object.fromEntries([...sourceFiles, ...controllerFiles, ...viewFiles, ...moduleFiles].sort().map((file) => [file, fileHash(file)])),
  schema: parseSchema(readText("Application/Schema.sql")),
  web: {
    controllers: parseControllers(readText("Web/Types.hs")),
    routes: parseRoutes(readText("Web/Routes.hs")),
    frontController: parseFrontController(readText("Web/FrontController.hs")),
    handlers: parseHandlers(controllerFiles),
    views: parseViews(viewFiles),
  },
  modules: parseHaskellModules(),
};

fs.mkdirSync(outputDir, { recursive: true });
writeJson("output/architecture/facts.json", facts);
console.log("Generated output/architecture/facts.json");
