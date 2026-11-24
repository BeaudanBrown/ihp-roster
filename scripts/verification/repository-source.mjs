import fs from "node:fs";
import path from "node:path";
export const repoRoot = process.cwd();
export function readText(relPath) {
  return fs.readFileSync(path.join(repoRoot, relPath), "utf8");
}
export function listFiles(dirs, predicate = () => true, root = repoRoot) {
  const out = [];
  const ignored = new Set([".git", ".direnv", "dist", "dist-newstyle", "node_modules", "result", "output", "build"]);
  const walk = (dir) => {
    if (!fs.existsSync(dir)) return;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (ignored.has(entry.name)) continue;
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.isFile() && predicate(full)) out.push(path.relative(root, full));
    }
  };
  for (const dir of dirs) walk(path.join(root, dir));
  return out.sort();
}
