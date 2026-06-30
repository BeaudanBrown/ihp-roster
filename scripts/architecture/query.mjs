import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { architectureResult, dotId, dotQuote, ensureDir, queryDir, readJsonFile, readStdinJson, renderDot, repoRoot, slug, writeText } from "./shared.mjs";

function ensureFacts() {
  const factsPath = path.join(repoRoot, "output/architecture/facts.json");
  if (fs.existsSync(factsPath)) return;
  const result = spawnSync(process.execPath, ["scripts/architecture/facts.mjs"], { cwd: repoRoot, encoding: "utf8" });
  if (result.status !== 0) throw new Error(`failed to generate facts: ${result.stderr || result.stdout}`);
}

function neighbors(graph, start, depth, direction) {
  const seen = new Set([start]);
  let frontier = [start];
  for (let level = 0; level < depth; level += 1) {
    const next = [];
    for (const node of frontier) {
      for (const edge of graph.edges) {
        const outgoing = edge.from === node && (direction === "downstream" || direction === "both");
        const incoming = edge.to === node && (direction === "upstream" || direction === "both");
        const other = outgoing ? edge.to : incoming ? edge.from : undefined;
        if (other && !seen.has(other)) {
          seen.add(other);
          next.push(other);
        }
      }
    }
    frontier = next;
  }
  return seen;
}

function graphFromFacts(facts) {
  const nodes = new Map();
  const edges = [];
  const addNode = (id, label, kind) => nodes.set(id, { id, label, kind });
  const addEdge = (from, to, label = "") => edges.push({ from, to, label });

  for (const table of facts.schema.tables) {
    addNode(`table:${table.name}`, table.name, "table");
    for (const fk of table.foreignKeys) addEdge(`table:${table.name}`, `table:${fk.referencesTable}`, fk.columns.join(", "));
  }
  const handlers = new Map(facts.web.handlers.map((handler) => [handler.action, handler]));
  for (const controller of facts.web.controllers) {
    addNode(`controller:${controller.name}`, controller.name, "controller");
    for (const action of controller.actions) {
      addNode(`action:${action.name}`, action.name, "action");
      addEdge(`controller:${controller.name}`, `action:${action.name}`, "declares");
      const handler = handlers.get(action.name);
      if (handler) {
        addNode(`module:${handler.module}`, handler.module, "module");
        addEdge(`action:${action.name}`, `module:${handler.module}`, "handler");
      }
      for (const field of action.fields || []) {
        const tableMatch = field.type.match(/Id\s+([A-Z][A-Za-z0-9_]*)/);
        if (tableMatch) addEdge(`action:${action.name}`, `table:${tableMatch[1].replace(/([a-z0-9])([A-Z])/g, "$1_$2").toLowerCase()}s`, field.name);
      }
    }
  }
  for (const module of facts.modules) {
    addNode(`module:${module.name}`, module.name, "module");
    for (const imported of module.imports) {
      if (facts.modules.some((m) => m.name === imported)) addEdge(`module:${module.name}`, `module:${imported}`, "imports");
    }
  }
  return { nodes, edges };
}

const payload = readStdinJson();
const args = payload.args || {};
const kind = args.kind;
const target = args.target;
const depth = Number(args.depth ?? 1);
const direction = args.direction || "both";
ensureFacts();
const facts = readJsonFile("output/architecture/facts.json");
const graph = graphFromFacts(facts);
const start = `${kind}:${target}`;
if (!graph.nodes.has(start)) {
  const candidates = [...graph.nodes.values()].filter((node) => node.kind === kind).map((node) => node.label).sort().slice(0, 25);
  throw new Error(`Unknown ${kind} target ${target}. Candidates include: ${candidates.join(", ")}`);
}
const selected = neighbors(graph, start, depth, direction);
const stem = `component-${slug(kind)}-${slug(target)}`;
const dotRel = `.pi/tmp/architecture-query/${stem}.dot`;
const svgRel = `.pi/tmp/architecture-query/${stem}.svg`;
ensureDir(queryDir);
const lines = [
  "digraph component_query {",
  "  graph [rankdir=LR, overlap=false, splines=true];",
  "  node [shape=box, fontsize=10];",
  "  edge [fontsize=9];",
];
const colors = { controller: "#edf7ed", action: "#fff7e6", table: "#eef7ff", module: "#f4f0ff" };
for (const id of selected) {
  const node = graph.nodes.get(id);
  lines.push(`  ${dotId(id)} [label=${dotQuote(`${node.label}\\n${node.kind}`)}, fillcolor=${dotQuote(colors[node.kind] || "#ffffff")}, style=filled];`);
}
for (const edge of graph.edges) {
  if (selected.has(edge.from) && selected.has(edge.to)) {
    lines.push(`  ${dotId(edge.from)} -> ${dotId(edge.to)}${edge.label ? ` [label=${dotQuote(edge.label)}]` : ""};`);
  }
}
lines.push("}");
writeText(dotRel, `${lines.join("\n")}\n`);
renderDot(dotRel, svgRel);
architectureResult(`Generated ${kind} component diagram for ${target}.`, [
  { path: svgRel, kind: "diagram", language: "svg" },
  { path: dotRel, kind: "source", language: "dot" },
], { generatedFrom: "output/architecture/facts.json", query: { kind, target, depth, direction } });
