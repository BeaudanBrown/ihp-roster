import { existsSync, readFileSync, readdirSync } from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);
const rootIndex = args.indexOf("--root");
const validArguments = args.length === 0
  || (args.length === 2 && rootIndex === 0 && args[1].trim() !== "");
if (!validArguments) {
  console.error("Usage: migration-enum-commit-boundary-check [--root REPOSITORY_ROOT]");
  process.exit(2);
}
const root = path.resolve(rootIndex >= 0 ? args[rootIndex + 1] : process.cwd());
const migrationDirectory = path.join(root, "Application/Migration");
if (!existsSync(migrationDirectory)) {
  console.error(`migration-enum-commit-boundary-check: missing ${migrationDirectory}`);
  process.exit(2);
}

function sqlStatements(source) {
  const statements = [];
  let statement = "";
  let index = 0;
  let blockCommentDepth = 0;
  let lineComment = false;
  let quote = null;
  let dollarQuote = null;

  while (index < source.length) {
    const char = source[index];
    const next = source[index + 1];

    if (lineComment) {
      if (char === "\n") {
        lineComment = false;
        statement += "\n";
      }
      index += 1;
      continue;
    }
    if (blockCommentDepth > 0) {
      if (char === "/" && next === "*") {
        blockCommentDepth += 1;
        index += 2;
      } else if (char === "*" && next === "/") {
        blockCommentDepth -= 1;
        index += 2;
      } else {
        index += 1;
      }
      continue;
    }
    if (dollarQuote !== null) {
      if (source.startsWith(dollarQuote, index)) {
        statement += dollarQuote;
        index += dollarQuote.length;
        dollarQuote = null;
      } else {
        statement += char;
        index += 1;
      }
      continue;
    }
    if (quote !== null) {
      statement += char;
      if (char === quote && next === quote) {
        statement += next;
        index += 2;
      } else {
        if (char === quote) quote = null;
        index += 1;
      }
      continue;
    }
    if (char === "-" && next === "-") {
      lineComment = true;
      statement += " ";
      index += 2;
      continue;
    }
    if (char === "/" && next === "*") {
      blockCommentDepth = 1;
      statement += " ";
      index += 2;
      continue;
    }
    if (char === "'" || char === '"') {
      quote = char;
      statement += char;
      index += 1;
      continue;
    }
    if (char === "$") {
      const match = source.slice(index).match(/^\$[A-Za-z_][A-Za-z0-9_]*\$|^\$\$/);
      if (match !== null) {
        dollarQuote = match[0];
        statement += dollarQuote;
        index += dollarQuote.length;
        continue;
      }
    }
    if (char === ";") {
      if (statement.trim() !== "") statements.push(statement.trim());
      statement = "";
      index += 1;
      continue;
    }
    statement += char;
    index += 1;
  }

  if (statement.trim() !== "") statements.push(statement.trim());
  return statements;
}

function sqlSyntax(statement) {
  let syntax = "";
  let index = 0;
  while (index < statement.length) {
    const char = statement[index];
    if (char === "'" || char === '"') {
      const quote = char;
      syntax += " ";
      index += 1;
      while (index < statement.length) {
        if (statement[index] === quote && statement[index + 1] === quote) {
          index += 2;
        } else if (statement[index] === quote) {
          index += 1;
          break;
        } else {
          index += 1;
        }
      }
      continue;
    }
    if (char === "$") {
      const match = statement.slice(index).match(/^\$[A-Za-z_][A-Za-z0-9_]*\$|^\$\$/);
      if (match !== null) {
        const closingIndex = statement.indexOf(match[0], index + match[0].length);
        syntax += " ";
        index = closingIndex < 0 ? statement.length : closingIndex + match[0].length;
        continue;
      }
    }
    syntax += char;
    index += 1;
  }
  return syntax;
}

const enumAddition = /^ALTER\s+TYPE\b[\s\S]*?\bADD\s+VALUE\b/i;
// The policy explicitly permits transaction-control statements around an enum
// addition, but never permits a use of the value in that same revision.
const transactionControl = /^(?:BEGIN|START\s+TRANSACTION|COMMIT|END|ROLLBACK|ABORT|SAVEPOINT|RELEASE(?:\s+SAVEPOINT)?|PREPARE\s+TRANSACTION)\b/i;
const migrationFiles = readdirSync(migrationDirectory)
  .filter((name) => name.endsWith(".sql"))
  .sort();
let enumMigrationCount = 0;
let failed = false;

for (const name of migrationFiles) {
  const relativeFile = path.join("Application/Migration", name);
  const statements = sqlStatements(readFileSync(path.join(root, relativeFile), "utf8"));
  const classifiedStatements = statements.map((statement) => ({
    statement,
    syntax: sqlSyntax(statement),
  }));
  if (!classifiedStatements.some(({ syntax }) => enumAddition.test(syntax))) continue;

  enumMigrationCount += 1;
  const mixedStatement = classifiedStatements.find(
    ({ syntax }) => !enumAddition.test(syntax) && !transactionControl.test(syntax),
  )?.statement;
  if (mixedStatement === undefined) continue;

  const summary = mixedStatement.replace(/\s+/g, " ").slice(0, 100);
  console.error(
    `migration-enum-commit-boundary-check: ${relativeFile}: ALTER TYPE ... ADD VALUE must be isolated; found additional statement "${summary}".`,
  );
  console.error(
    "PostgreSQL cannot use a newly added enum value until commit (SQLSTATE 55P04), and the pinned IHP runner executes a migration revision in one transaction.",
  );
  console.error(
    "Move data, default, index, or constraint operations to a later migration revision. The real-runner migration rehearsal remains authoritative.",
  );
  failed = true;
}

if (failed) {
  process.exitCode = 1;
} else {
  console.log(
    `migration-enum-commit-boundary-check: ok (${migrationFiles.length} migrations, ${enumMigrationCount} enum-add migrations)`,
  );
}
