import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import path from "node:path";

const moduleInventoryPath = "Config/nix/production-module-inventory.tsv";
const scriptInventoryPath = "Config/nix/production-script-inventory.tsv";
const executableInventoryPath = "Config/nix/production-executable-inventory.tsv";
const frontendContractToolInventoryPath = "Config/nix/frontend-contract-tool-module-inventory.tsv";
const frontendContractToolingOnlyPolicyPath = "Config/nix/frontend-contract-tooling-only-policy.tsv";
const productionPackageDependencyInventoryPath = "Config/nix/production-package-dependency-inventory.tsv";
const mode = process.argv[2] ?? "--check";

function fail(message) {
  console.error(`production-inventory: ${message}`);
  process.exitCode = 1;
}

function walk(directory) {
  if (!existsSync(directory)) return [];
  return readdirSync(directory).sort().flatMap((name) => {
    const relative = path.join(directory, name);
    return statSync(relative).isDirectory() ? walk(relative) : [relative];
  });
}

function moduleName(file, text) {
  return text.match(/^\s*module\s+([A-Za-z0-9_.]+)/m)?.[1]
    ?? file.replace(/\.hs$/, "").split(path.sep).join(".");
}

function imports(text, file) {
  // Explicitly braced module bodies permit imports after semicolons instead of
  // at line starts. Reject any such import token directly rather than trying
  // to locate a comment-sensitive module-header `where`. False positives in a
  // comment/string fail safely; they can never silently shrink the closure.
  if (/(?:\{|;)\s*import\b/.test(text)) {
    fail(`${file}: explicit braced import layout is unsupported; inventory parsing fails closed`);
    return [];
  }
  const found = [];
  for (const [index, rawLine] of text.split("\n").entries()) {
    const line = rawLine.trimStart();
    if (!/^import(?:\s|$)/.test(line)) continue;
    const match = line.match(/^import\s+(?:\{-#\s*SOURCE\s*#-}\s+)?(?:safe\s+)?(?:qualified\s+)?(?:"[^"]+"\s+)?([A-Z][A-Za-z0-9_.]+)(?:\s+qualified)?(?:\s|$)/);
    if (!match) {
      fail(`${file}:${index + 1}: unsupported import declaration; inventory parsing fails closed`);
      continue;
    }
    found.push(match[1]);
  }
  return found;
}

function parseTsv(file, columns) {
  if (!existsSync(file)) return null;
  const lines = readFileSync(file, "utf8").trimEnd().split("\n");
  if (lines.shift() !== columns.join("\t")) {
    fail(`${file}: expected header ${columns.join("\\t")}`);
    return [];
  }
  return lines.filter(Boolean).map((line, index) => {
    const values = line.split("\t");
    if (values.length !== columns.length) {
      fail(`${file}:${index + 2}: expected ${columns.length} tab-separated fields`);
    }
    return Object.fromEntries(columns.map((column, i) => [column, values[i] ?? ""]));
  });
}

const scriptRows = parseTsv(scriptInventoryPath, ["script", "packaging", "category", "consumer", "reason"]);
if (!scriptRows) {
  fail(`missing ${scriptInventoryPath}`);
  process.exit();
}

const scriptFiles = walk("Application/Script")
  .filter((file) => file.endsWith(".hs") && !file.endsWith("/Prelude.hs"));
const scriptNames = scriptFiles.map((file) => path.basename(file, ".hs"));
const rowByScript = new Map();
for (const row of scriptRows) {
  if (rowByScript.has(row.script)) fail(`${scriptInventoryPath}: duplicate ${row.script}`);
  if (!scriptNames.includes(row.script)) fail(`${scriptInventoryPath}: unknown script ${row.script}`);
  if (!new Set(["production", "development"]).has(row.packaging)) fail(`${scriptInventoryPath}: invalid packaging for ${row.script}`);
  if (!row.category || !row.consumer || !row.reason) fail(`${scriptInventoryPath}: ${row.script} needs category, consumer, and reason`);
  rowByScript.set(row.script, row);
}
for (const script of scriptNames) {
  if (!rowByScript.has(script)) fail(`${scriptInventoryPath}: unclassified Application/Script/${script}.hs`);
}

const productionScripts = scriptRows.filter((row) => row.packaging === "production");
for (const row of productionScripts) {
  if (!existsSync(row.consumer)) {
    fail(`${scriptInventoryPath}: ${row.script} consumer does not exist: ${row.consumer}`);
  } else if (!readFileSync(row.consumer, "utf8").includes(row.script)) {
    fail(`${scriptInventoryPath}: ${row.consumer} does not reference ${row.script}`);
  }
}

const executableRows = parseTsv(executableInventoryPath, ["executable", "category", "consumer", "marker", "reason"]);
if (!executableRows) {
  fail(`missing ${executableInventoryPath}`);
  process.exit();
}
const executableNames = new Set();
for (const row of executableRows) {
  if (executableNames.has(row.executable)) fail(`${executableInventoryPath}: duplicate ${row.executable}`);
  if (!row.category || !row.consumer || !row.marker || !row.reason) fail(`${executableInventoryPath}: ${row.executable} needs category, consumer, marker, and reason`);
  if (!existsSync(row.consumer)) fail(`${executableInventoryPath}: ${row.executable} consumer does not exist: ${row.consumer}`);
  else if (!readFileSync(row.consumer, "utf8").includes(row.marker)) fail(`${executableInventoryPath}: ${row.consumer} lacks marker ${row.marker} for ${row.executable}`);
  executableNames.add(row.executable);
}
const productionScriptNames = new Set(productionScripts.map((row) => row.script));
for (const script of productionScriptNames) if (!executableNames.has(script)) fail(`production script ${script} is absent from executable inventory`);
for (const executable of executableNames) {
  if (!["RunProdServer", "RunJobs"].includes(executable) && !productionScriptNames.has(executable)) fail(`packaged script executable ${executable} is not production-classified`);
}
if (!executableNames.has("RunProdServer") || !executableNames.has("RunJobs")) fail(`${executableInventoryPath}: app and worker runtime roots are required`);

const haskellFiles = ["Main.hs", "WorkerMain.hs", ...walk("Application"), ...walk("Web"), ...walk("Config")]
  .filter((file) => file.endsWith(".hs"));
const modules = new Map();
for (const file of haskellFiles) {
  const text = readFileSync(file, "utf8");
  const name = moduleName(file, text);
  if (modules.has(name)) fail(`duplicate local module ${name}: ${modules.get(name).file} and ${file}`);
  modules.set(name, { file, imports: imports(text, file) });
}
const roots = ["Main", "WorkerMain", "Config", ...productionScripts.map((row) => `Application.Script.${row.script}`)];
for (const rootModule of roots) if (!modules.has(rootModule)) fail(`missing production root module ${rootModule}`);
const closureForRoot = (rootModule) => {
  const reached = new Set();
  const queue = [rootModule];
  while (queue.length > 0) {
    const name = queue.shift();
    if (reached.has(name) || !modules.has(name)) continue;
    reached.add(name);
    queue.push(...modules.get(name).imports);
  }
  return reached;
};
const closureByRoot = new Map(roots.map((rootModule) => [rootModule, closureForRoot(rootModule)]));
const frontendContractToolRoots = [
  "Application.Script.GenerateFrontendContracts",
  "Application.Script.GenerateFrontendSurfaceAdapters",
  "Application.Script.GenerateBepisArchitectureContracts",
];
for (const rootModule of frontendContractToolRoots) if (!modules.has(rootModule)) fail(`missing frontend-contract tool root module ${rootModule}`);
const frontendContractToolReachableFrom = new Map();
for (const rootModule of frontendContractToolRoots) {
  for (const name of closureForRoot(rootModule)) if (!frontendContractToolReachableFrom.has(name)) frontendContractToolReachableFrom.set(name, rootModule);
}
const reachableFrom = new Map();
for (const [rootModule, closure] of closureByRoot) {
  for (const name of closure) if (!reachableFrom.has(name)) reachableFrom.set(name, rootModule);
}
const testOnlyImportPrefixes = ["IHP.Hspec", "Test.Hspec", "Test.QuickCheck"];
const externalImportSources = new Map();
for (const [name, rootModule] of reachableFrom) {
  const entry = modules.get(name);
  for (const imported of entry.imports) {
    if (testOnlyImportPrefixes.some((prefix) => imported === prefix || imported.startsWith(`${prefix}.`))) {
      fail(`${entry.file}: production module imports test-only interface ${imported}`);
    }
    if (modules.has(imported)) continue;
    if (!externalImportSources.has(imported)) externalImportSources.set(imported, new Set());
    externalImportSources.get(imported).add(`${entry.file} via ${rootModule}`);
  }
}

const existingProductionPackageDependencyRows = parseTsv(
  productionPackageDependencyInventoryPath,
  ["module", "package", "reason"],
) ?? [];
const existingProductionPackageDependencyByModule = new Map(
  existingProductionPackageDependencyRows.map((row) => [row.module, row]),
);
const renderedProductionPackageDependencies = [
  "module\tpackage\treason",
  ...[...externalImportSources.keys()].sort().map((imported) => {
    const existing = existingProductionPackageDependencyByModule.get(imported);
    return [imported, existing?.package ?? "UNCLASSIFIED", [...externalImportSources.get(imported)][0]].join("\t");
  }),
  "",
].join("\n");
if (mode !== "--write-dependencies") {
  if (!existsSync(productionPackageDependencyInventoryPath)) {
    fail(`missing ${productionPackageDependencyInventoryPath}; run with --write-dependencies and classify each external import`);
  } else {
    const seenDependencyModules = new Set();
    for (const row of existingProductionPackageDependencyRows) {
      if (seenDependencyModules.has(row.module)) fail(`${productionPackageDependencyInventoryPath}: duplicate ${row.module}`);
      seenDependencyModules.add(row.module);
      if (!externalImportSources.has(row.module)) fail(`${productionPackageDependencyInventoryPath}: stale external import ${row.module}`);
      if (!row.package || row.package === "UNCLASSIFIED") {
        fail(`${productionPackageDependencyInventoryPath}: undeclared external production import ${row.module}; imported by ${[...externalImportSources.get(row.module)].join(", ")}`);
      } else if (!/^[A-Za-z0-9][A-Za-z0-9-]*$/.test(row.package)) {
        fail(`${productionPackageDependencyInventoryPath}: invalid Cabal package name ${row.package} for ${row.module}`);
      }
      const expectedReason = [...externalImportSources.get(row.module)][0];
      if (row.reason !== expectedReason) {
        fail(`${productionPackageDependencyInventoryPath}: stale provenance for ${row.module}; expected ${expectedReason}`);
      }
    }
    for (const [imported, sources] of externalImportSources) {
      if (!seenDependencyModules.has(imported)) {
        fail(`${productionPackageDependencyInventoryPath}: undeclared external production import ${imported}; imported by ${[...sources].join(", ")}`);
      }
    }
  }
}

function exclusion(file) {
  if (file.startsWith("Application/Script/")) {
    const script = path.basename(file, ".hs");
    const row = rowByScript.get(script);
    if (script === "Prelude") return ["development-support", "Shared run-script prelude; production scripts reach it transitively when required"];
    return [row.category, row.reason];
  }
  if (file.startsWith("Application/Fixture/DevFixtures") || file === "Application/Fixture/DevFixtures.hs") return ["development-fixture", "Synthetic local development data only"];
  if (file === "Application/Fixture.hs" || file.startsWith("Application/Fixture/")) return ["fixture", "Seed, profile, or test fixture outside deployed runtime closure"];
  if (file.startsWith("Application/Architecture/") || file.includes("/HaskellAdapter/") || file.endsWith("/Architecture.hs") || file.endsWith("/Contracts.hs") || file.endsWith("/TypeScript.hs")) return ["build-tooling", "Generator or architecture tooling outside deployed runtime closure"];
  return ["unreachable", "Not reachable from an explicit production executable root"];
}

const expectedRows = haskellFiles.sort().map((file) => {
  const name = [...modules].find(([, entry]) => entry.file === file)?.[0];
  const owner = reachableFrom.get(name);
  if (owner) return { file, packaging: "production", category: ["Main", "WorkerMain", "Config"].includes(owner) ? "runtime" : "operational-script-closure", owner, reason: `Reachable from ${owner}` };
  const [category, reason] = exclusion(file);
  return { file, packaging: "development", category, owner: "-", reason };
});

const rendered = [
  "path\tpackaging\tcategory\towner\treason",
  ...expectedRows.map((row) => [row.file, row.packaging, row.category, row.owner, row.reason].join("\t")),
  "",
].join("\n");
const toolingOnlyPolicyRows = parseTsv(frontendContractToolingOnlyPolicyPath, ["path", "reason"]);
if (!toolingOnlyPolicyRows) fail(`missing ${frontendContractToolingOnlyPolicyPath}`);
const toolingOnlyPolicy = new Map();
for (const row of toolingOnlyPolicyRows ?? []) {
  if (toolingOnlyPolicy.has(row.path)) fail(`${frontendContractToolingOnlyPolicyPath}: duplicate ${row.path}`);
  if (!row.reason) fail(`${frontendContractToolingOnlyPolicyPath}: ${row.path} needs a reason`);
  toolingOnlyPolicy.set(row.path, row.reason);
}
for (const [file] of toolingOnlyPolicy) {
  const name = [...modules].find(([, entry]) => entry.file === file)?.[0];
  if (!name || !frontendContractToolReachableFrom.has(name)) fail(`${frontendContractToolingOnlyPolicyPath}: ${file} is not in the frontend-contract tool closure`);
  if (reachableFrom.has(name)) fail(`${frontendContractToolingOnlyPolicyPath}: tooling-only module reached production: ${file}`);
}
const frontendContractToolRows = [...frontendContractToolReachableFrom]
  .map(([name, owner]) => {
    const file = modules.get(name).file;
    const sharedWithProduction = reachableFrom.has(name);
    if (!sharedWithProduction && !toolingOnlyPolicy.has(file)) fail(`${frontendContractToolingOnlyPolicyPath}: unclassified tooling-only module ${file}`);
    return {
      file,
      category: toolingOnlyPolicy.has(file) ? "tooling-only" : "shared-authority",
      owner,
      reason: toolingOnlyPolicy.get(file)
        ?? "Canonical Haskell authority consumed by runtime and frontend-contract tooling",
    };
  })
  .sort((left, right) => left.file.localeCompare(right.file));
const renderedFrontendContractTools = [
  "path\tcategory\towner\treason",
  ...frontendContractToolRows.map((row) => [row.file, row.category, row.owner, row.reason].join("\t")),
  "",
].join("\n");

if (mode === "--write") {
  writeFileSync(moduleInventoryPath, rendered);
  console.log(`production-inventory: wrote ${expectedRows.length} module classifications`);
} else if (mode === "--write-tooling") {
  writeFileSync(frontendContractToolInventoryPath, renderedFrontendContractTools);
  console.log(`production-inventory: wrote ${frontendContractToolRows.length} frontend-contract tool module classifications`);
} else if (mode === "--write-dependencies") {
  writeFileSync(productionPackageDependencyInventoryPath, renderedProductionPackageDependencies);
  console.log(`production-inventory: wrote ${externalImportSources.size} external production import classifications`);
} else if (mode === "--check") {
  if (!existsSync(moduleInventoryPath)) fail(`missing ${moduleInventoryPath}; run with --write`);
  else if (readFileSync(moduleInventoryPath, "utf8") !== rendered) fail(`${moduleInventoryPath} is stale; run with --write and review classification changes`);
  if (!existsSync(frontendContractToolInventoryPath)) fail(`missing ${frontendContractToolInventoryPath}; run with --write-tooling`);
  else if (readFileSync(frontendContractToolInventoryPath, "utf8") !== renderedFrontendContractTools) fail(`${frontendContractToolInventoryPath} is stale; run with --write-tooling and review package seam changes`);
  if (!process.exitCode) console.log(`production-inventory: ok (${reachableFrom.size} production modules, ${frontendContractToolRows.length} frontend-contract tool modules, ${productionScripts.length} production scripts, ${scriptRows.length - productionScripts.length} development scripts, ${executableRows.length} packaged executables)`);
} else {
  fail(`unknown mode ${mode}; expected --check, --write, --write-tooling, or --write-dependencies`);
}
