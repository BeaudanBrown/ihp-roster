#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { repoRoot } from "./shared.mjs";

function stripSqlComments(sql) {
  return sql
    .replace(/--[^\n]*/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "");
}

export function parseApplicationSchemaTables(sql) {
  const source = stripSqlComments(sql);
  return [...source.matchAll(/\bCREATE\s+TABLE\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/gi)].map((match) => match[1]);
}

function stripHaskellComments(source) {
  return source
    .replace(/--[^\n]*/g, "")
    .replace(/\{-[\s\S]*?-\}/g, "");
}

export function parseResetManifest(source) {
  const activeSource = stripHaskellComments(source);
  const definition = activeSource.match(/\bapplicationTableNames\s*=\s*\[([\s\S]*?)\](?=\s*(?:\n[A-Za-z_][A-Za-z0-9_']*\s*::|$))/);
  if (!definition) {
    throw new Error("applicationTableNames must be an explicit list of string literals");
  }
  const body = definition[1];
  const names = [...body.matchAll(/"([A-Za-z_][A-Za-z0-9_]*)"/g)].map((match) => match[1]);
  const nonLiteral = body.replace(/"[A-Za-z_][A-Za-z0-9_]*"/g, "").replace(/[\s,]/g, "");
  if (nonLiteral.length > 0) {
    throw new Error(`applicationTableNames must contain only string literals; found: ${nonLiteral}`);
  }
  return names;
}

export function checkResetManifest(schemaSource, manifestSource) {
  const schemaTables = parseApplicationSchemaTables(schemaSource);
  const manifestTables = parseResetManifest(manifestSource);
  const schemaSet = new Set(schemaTables);
  const manifestSet = new Set(manifestTables);
  const duplicates = manifestTables.filter((name, index) => manifestTables.indexOf(name) !== index);
  const errors = [...new Set(duplicates)].sort().map((name) => `reset manifest duplicates table: ${name}`);
  errors.push(...schemaTables.filter((name) => !manifestSet.has(name)).sort().map((name) => `reset manifest is missing application table: ${name}`));
  errors.push(...manifestTables.filter((name) => !schemaSet.has(name)).sort().map((name) => `reset manifest includes non-application table: ${name}`));
  return errors;
}

export function checkRepositoryResetManifest() {
  const schemaPath = path.join(repoRoot, "Application/Schema.sql");
  const manifestPath = path.join(repoRoot, "Application/Fixture/Reset.hs");
  return checkResetManifest(fs.readFileSync(schemaPath, "utf8"), fs.readFileSync(manifestPath, "utf8"));
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  try {
    const errors = checkRepositoryResetManifest();
    if (errors.length > 0) {
      console.error(`Fixture reset manifest check failed with ${errors.length} error(s):`);
      errors.forEach((error) => console.error(`- ${error}`));
      process.exitCode = 1;
    } else {
      console.log("Fixture reset manifest covers every application-schema table with static literals.");
    }
  } catch (error) {
    console.error(`Fixture reset manifest check failed: ${error.message}`);
    process.exitCode = 1;
  }
}
