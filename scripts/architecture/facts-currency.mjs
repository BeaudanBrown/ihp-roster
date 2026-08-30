import { createHash } from "node:crypto";
import { fileHash, listFiles, repoRoot } from "./shared.mjs";

export const architectureFactsRecoveryCommand = "bash ./bin/in-env architecture-facts";

const explicitFactInputs = [
  "Application/Schema.sql",
  "Web/Types.hs",
  "Web/Routes.hs",
  "Web/FrontController.hs",
  "Web/View/Layout.hs",
  "Config/nix/scripts/architecture/contracts",
  "Config/nix/scripts/architecture/facts",
  "output/architecture/bepis-contracts.json",
  "scripts/architecture/facts.mjs",
  "scripts/architecture/facts-currency.mjs",
  "scripts/architecture/layout-policy.mjs",
  "scripts/architecture/shared.mjs",
  "scripts/architecture/wiring-policy.mjs",
  "scripts/architecture/wiring-source.mjs",
];

function unique(values) {
  return [...new Set(values)].sort();
}

export function architectureFactInputFiles(root = repoRoot) {
  const haskellFiles = listFiles(["Application", "Web", "Test"], (file) => file.endsWith(".hs"), root);
  const frontendFiles = listFiles(
    ["frontend/ts"],
    (file) => /\.(ts|js|hs|tsx|jsx)$/.test(file),
    root,
  );
  return unique([...explicitFactInputs, ...haskellFiles, ...frontendFiles]);
}

export function architectureFactFingerprint(root = repoRoot) {
  const files = Object.fromEntries(
    architectureFactInputFiles(root).map((relPath) => [relPath, fileHash(relPath, root)]),
  );
  const digest = createHash("sha256").update(JSON.stringify(files)).digest("hex");
  return { version: 1, algorithm: "sha256", digest, files };
}

function changedInputs(recorded, current) {
  const paths = unique([...Object.keys(recorded || {}), ...Object.keys(current || {})]);
  return paths.filter((relPath) => recorded?.[relPath] !== current?.[relPath]);
}

export function assertArchitectureFactsCurrent(facts, root = repoRoot) {
  const recorded = facts?.inputFingerprint;
  const current = architectureFactFingerprint(root);
  if (recorded?.version === current.version && recorded?.algorithm === current.algorithm && recorded?.digest === current.digest) {
    return current;
  }

  const changed = changedInputs(recorded?.files, current.files);
  const detail = recorded
    ? `${changed.length} architecture fact input(s) changed${changed.length ? `: ${changed.slice(0, 5).join(", ")}${changed.length > 5 ? ", …" : ""}` : ""}`
    : "the facts artifact has no current input fingerprint";
  throw new Error(`Stale output/architecture/facts.json: ${detail}. Run \`${architectureFactsRecoveryCommand}\` and retry.`);
}
