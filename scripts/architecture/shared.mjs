import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";

export const repoRoot = process.cwd();
export const outputDir = path.join(repoRoot, "output", "architecture");
export const queryDir = path.join(repoRoot, ".pi", "tmp", "architecture-query");
export const traceDir = path.join(repoRoot, ".pi", "tmp", "architecture-trace");

export function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

export function readText(relPath) {
  return fs.readFileSync(path.join(repoRoot, relPath), "utf8");
}

export function writeText(relPath, content) {
  const full = path.join(repoRoot, relPath);
  ensureDir(path.dirname(full));
  const temp = path.join(path.dirname(full), `.${path.basename(full)}.${process.pid}.${Date.now()}.tmp`);
  fs.writeFileSync(temp, content);
  fs.renameSync(temp, full);
  return relPath;
}

export function writeJson(relPath, value) {
  return writeText(relPath, `${JSON.stringify(value, null, 2)}\n`);
}

export function fileHash(relPath) {
  const full = path.join(repoRoot, relPath);
  if (!fs.existsSync(full)) return null;
  return createHash("sha256").update(fs.readFileSync(full)).digest("hex");
}

export function listFiles(dirs, predicate = () => true) {
  const out = [];
  const ignored = new Set([".git", ".direnv", "dist", "dist-newstyle", "node_modules", "result", "output", "build"]);
  const walk = (dir) => {
    if (!fs.existsSync(dir)) return;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (ignored.has(entry.name)) continue;
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.isFile() && predicate(full)) out.push(path.relative(repoRoot, full));
    }
  };
  for (const dir of dirs) walk(path.join(repoRoot, dir));
  return out.sort();
}

export function dotId(value) {
  return String(value).replace(/[^A-Za-z0-9_]/g, "_").replace(/^([0-9])/, "_$1");
}

export function dotQuote(value) {
  return JSON.stringify(String(value));
}

export function slug(value) {
  return String(value).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "item";
}

export function renderDot(dotRelPath, svgRelPath) {
  const dotPath = path.join(repoRoot, dotRelPath);
  const svgPath = path.join(repoRoot, svgRelPath);
  ensureDir(path.dirname(svgPath));
  const result = spawnSync("dot", ["-Tsvg", dotPath, "-o", svgPath], {
    cwd: repoRoot,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    throw new Error(`dot failed for ${dotRelPath}:\n${result.stdout || ""}${result.stderr || ""}`);
  }
  return svgRelPath;
}

export function readJsonFile(relPath) {
  return JSON.parse(readText(relPath));
}

export function maybeReadJsonFile(relPath) {
  const full = path.join(repoRoot, relPath);
  if (!fs.existsSync(full)) return undefined;
  return JSON.parse(fs.readFileSync(full, "utf8"));
}

export function readStdinJson() {
  const input = fs.readFileSync(0, "utf8").trim();
  if (input) return JSON.parse(input);
  if (process.env.PI_ARCHITECTURE_QUERY_PAYLOAD_JSON) return JSON.parse(process.env.PI_ARCHITECTURE_QUERY_PAYLOAD_JSON);
  return { name: process.env.PI_ARCHITECTURE_QUERY_NAME, args: JSON.parse(process.env.PI_ARCHITECTURE_QUERY_ARGS_JSON || "{}") };
}

export function architectureResult(summary, artifacts = [], provenance = {}, extra = {}) {
  process.stdout.write(`${JSON.stringify({ summary, ...extra, artifacts, provenance }, null, 2)}\n`);
}
