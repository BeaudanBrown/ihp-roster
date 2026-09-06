import { readdirSync, readFileSync } from "node:fs";
import { resolve, relative } from "node:path";

// Metafile paths (including resolved import paths) are relative to esbuild's cwd.
const root = process.cwd();
const metadata = JSON.parse(readFileSync(process.argv[2], "utf8"));
const inputs = new Map(Object.entries(metadata.inputs).map(([path, input]) => [resolve(root, path), input]));
const reachable = new Set();
function visit(path) {
    if (reachable.has(path)) return;
    reachable.add(path);
    const input = inputs.get(path);
    if (!input) throw new Error(`Missing bundled input: ${relative(root, path)}`);
    for (const edge of input.imports) {
        if (!edge.external && edge.kind === "import-statement") visit(resolve(root, edge.path));
    }
}
visit(resolve(root, "frontend/ts/tests/main.ts"));

function discover(directory) {
    return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
        const path = resolve(directory, entry.name);
        if (entry.isDirectory()) return discover(path);
        return entry.isFile() && entry.name.endsWith(".test.ts") ? [path] : [];
    });
}
const missing = discover(resolve(root, "frontend/ts")).filter((path) => !reachable.has(path)).sort();
if (missing.length) {
    console.error("Frontend tests missing static registration from frontend/ts/tests/main.ts:");
    for (const path of missing) console.error(`  ${relative(root, path)}`);
    process.exitCode = 1;
}
