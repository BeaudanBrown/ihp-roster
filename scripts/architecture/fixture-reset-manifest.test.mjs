import assert from "node:assert/strict";
import test from "node:test";
import {
  checkResetManifest,
  parseApplicationSchemaTables,
  parseResetManifest,
} from "./fixture-reset-manifest.mjs";

const schema = `
-- CREATE TABLE ignored_comment (id UUID);
CREATE TABLE users (
    id UUID PRIMARY KEY
);
CREATE TABLE audit_events (
    id UUID PRIMARY KEY
);
`;

const manifest = `
applicationTableNames :: [Text]
applicationTableNames =
    [ "users"
    , "audit_events"
    ]
`;

test("parses application tables and the checked static reset manifest", () => {
  assert.deepEqual(parseApplicationSchemaTables(schema), ["users", "audit_events"]);
  assert.deepEqual(parseResetManifest(manifest), ["users", "audit_events"]);
  assert.deepEqual(checkResetManifest(schema, manifest), []);
});

test("reports missing, extra, and duplicate reset entries", () => {
  const invalidManifest = `
applicationTableNames :: [Text]
applicationTableNames = ["users", "users", "framework_migrations"]
`;

  assert.deepEqual(checkResetManifest(schema, invalidManifest), [
    "reset manifest duplicates table: users",
    "reset manifest is missing application table: audit_events",
    "reset manifest includes non-application table: framework_migrations",
  ]);
});

test("rejects a dynamic reset manifest instead of discovering database tables", () => {
  const dynamicManifest = `
applicationTableNames :: [Text]
applicationTableNames = discoverTablesFromDatabase
`;

  assert.throws(
    () => parseResetManifest(dynamicManifest),
    /applicationTableNames must be an explicit list of string literals/,
  );
});

test("ignores commented-out literal manifests that precede a dynamic binding", () => {
  const bypassAttempt = `
-- applicationTableNames = ["users", "audit_events"]
{-
applicationTableNames = ["users", "audit_events"]
-}
applicationTableNames :: [Text]
applicationTableNames = discoverTablesFromDatabase
`;

  assert.throws(
    () => parseResetManifest(bypassAttempt),
    /applicationTableNames must be an explicit list of string literals/,
  );
});

test("rejects a literal manifest with a dynamic suffix", () => {
  const bypassAttempt = `
applicationTableNames :: [Text]
applicationTableNames = ["users", "audit_events"] <> discoverTablesFromDatabase
`;

  assert.throws(
    () => parseResetManifest(bypassAttempt),
    /applicationTableNames must be an explicit list of string literals/,
  );
});
