#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const failures = [];

function trackedMarkdownFiles() {
  const result = spawnSync("git", ["ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "*.md"], {
    cwd: repoRoot,
    encoding: "buffer",
  });
  if (result.status !== 0) throw new Error(result.stderr.toString("utf8"));
  return result.stdout.toString("utf8").split("\0").filter((file) => file && !file.startsWith(".pi/"));
}

function localDestination(raw, file, root) {
  let destination = raw.trim();
  if (destination.startsWith("<") && destination.endsWith(">")) destination = destination.slice(1, -1);
  destination = destination.replace(/\s+["'][^"']*["']$/, "");
  if (!destination || destination.startsWith("/") || /^[a-z][a-z0-9+.-]*:/i.test(destination)) return null;
  const hashAt = destination.indexOf("#");
  const rawPath = (hashAt === -1 ? destination : destination.slice(0, hashAt)).split("?", 1)[0];
  const fragment = hashAt === -1 ? null : decodeURIComponent(destination.slice(hashAt + 1));
  const decodedPath = decodeURIComponent(rawPath);
  return {
    resolved: path.resolve(root, path.dirname(file), decodedPath || path.basename(file)),
    fragment,
  };
}

export function markdownAnchors(text) {
  const anchors = new Set();
  const counts = new Map();
  let fence = null;
  for (const line of text.split("\n")) {
    const fenceMatch = line.match(/^\s*(```+|~~~+)/);
    if (fenceMatch) {
      if (!fence) fence = fenceMatch[1][0];
      else if (fence === fenceMatch[1][0]) fence = null;
      continue;
    }
    if (fence) continue;
    const heading = line.match(/^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$/);
    if (heading) {
      const plain = heading[1]
        .replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1")
        .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
        .replace(/<[^>]+>/g, "")
        .replace(/[`*_~]/g, "");
      const base = plain.toLowerCase().trim().replace(/[^\p{L}\p{N}\s_-]/gu, "").replace(/\s/g, "-");
      const count = counts.get(base) || 0;
      anchors.add(count === 0 ? base : `${base}-${count}`);
      counts.set(base, count + 1);
    }
    for (const match of line.matchAll(/<(?:a\s+[^>]*(?:id|name)|[^>]+\s+id)=["']([^"']+)["'][^>]*>/gi)) anchors.add(match[1]);
  }
  return anchors;
}

const anchorCache = new Map();
function anchorsFor(file) {
  if (!anchorCache.has(file)) anchorCache.set(file, markdownAnchors(fs.readFileSync(file, "utf8")));
  return anchorCache.get(file);
}

function activeMarkdownText(text) {
  let fence = null;
  return text.split("\n").map((line) => {
    const fenceMatch = line.match(/^\s*(```+|~~~+)/);
    if (fenceMatch) {
      if (!fence) fence = fenceMatch[1][0];
      else if (fence === fenceMatch[1][0]) fence = null;
      return " ".repeat(line.length);
    }
    if (fence) return " ".repeat(line.length);
    return line.replace(/(`+)[^`\n]*\1/g, (code) => " ".repeat(code.length));
  }).join("\n");
}

export function checkLocalLinks(file, text, root = repoRoot) {
  const linkFailures = [];
  const destinations = [];
  const activeText = activeMarkdownText(text);
  for (const match of activeText.matchAll(/!?(?:\[[^\]]*\])\(([^)]+)\)/g)) destinations.push(match[1]);
  for (const match of activeText.matchAll(/^\s*\[[^\]]+\]:\s*(\S+)/gm)) destinations.push(match[1]);
  for (const raw of destinations) {
    const destination = localDestination(raw, file, root);
    if (!destination) continue;
    if (!fs.existsSync(destination.resolved)) {
      linkFailures.push(`${file}: broken local Markdown reference ${raw}`);
      continue;
    }
    if (destination.fragment !== null && destination.resolved.endsWith(".md") && !anchorsFor(destination.resolved).has(destination.fragment)) {
      linkFailures.push(`${file}: broken Markdown anchor ${raw}`);
    }
  }
  return linkFailures;
}

const retiredFrontendTerms = [
  "GenerateFrontendContractsGhc",
  "FrontendSurfaceGhc",
  "Surface.Ghc",
  "Surface.Adapter",
  "TypedLiveSurfaceDefinition",
  "typed-live",
  "data-live-update-surface",
  "IHP Auto Refresh",
  "ihp-auto-refresh",
  "Morphdom",
  "morphdom",
  "SurfaceProjection",
  "Application.Helper.Frontend.",
  "omnibus registry",
  "GHC probe",
  "GHC API extraction",
  "compiler-type inspection",
];

export function runDocumentationCheck() {
  failures.length = 0;
  const files = trackedMarkdownFiles();
  for (const file of files) {
    const text = fs.readFileSync(path.join(repoRoot, file), "utf8");
    failures.push(...checkLocalLinks(file, text));
    for (const term of retiredFrontendTerms) {
      if (text.includes(term)) failures.push(`${file}: retired frontend/runtime term ${term}`);
    }
  }

  const archiveReadme = fs.readFileSync(path.join(repoRoot, "docs/archive/README.md"), "utf8");
  for (const file of files.filter((file) => file.startsWith("docs/archive/") && file !== "docs/archive/README.md")) {
    const relative = path.relative("docs/archive", file);
    if (!archiveReadme.includes(`\`${relative}\``)) failures.push(`${file}: retained archive is not justified in docs/archive/README.md`);
  }

  if (failures.length > 0) {
    console.error(`documentation-check failed with ${failures.length} error(s):`);
    for (const failure of failures) console.error(`- ${failure}`);
    return 1;
  }

  console.log(`documentation-check: ${files.length} Markdown files, local references and retained archives valid`);
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = runDocumentationCheck();
}
