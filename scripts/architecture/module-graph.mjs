import { rmSync } from "node:fs";
import { dotId, dotQuote, maybeReadJsonFile, renderDot, writeText } from "./shared.mjs";
if (process.env.ARCHITECTURE_FACTS_CURRENT !== "1") await import("./facts.mjs");

const facts = maybeReadJsonFile("output/architecture/facts.json");
if (!facts) throw new Error("Missing output/architecture/facts.json");
const localModules = new Set(facts.modules.map((module) => module.name));
const interestingPrefixes = ["Application.", "Web.", "Generated."];
const lines = [
  "digraph module_graph {",
  "  graph [rankdir=LR, overlap=false, splines=true];",
  "  node [shape=box, fontsize=10];",
  "  edge [fontsize=9, color=\"#555555\"];",
];

for (const module of facts.modules) {
  const fill = module.name.startsWith("Web.Controller") ? "#f4f0ff" : module.name.startsWith("Web.View") ? "#eef7ff" : module.name.startsWith("Application.Helper") ? "#edf7ed" : "#ffffff";
  lines.push(`  ${dotId(module.name)} [label=${dotQuote(module.name)}, style=filled, fillcolor=${dotQuote(fill)}];`);
}

for (const module of facts.modules) {
  for (const imported of module.imports) {
    if (localModules.has(imported) || interestingPrefixes.some((prefix) => imported.startsWith(prefix))) {
      lines.push(`  ${dotId(module.name)} -> ${dotId(imported)};`);
    }
  }
}

lines.push("}");
writeText("output/architecture/module-graph.dot", `${lines.join("\n")}\n`);
if (process.env.ARCHITECTURE_SKIP_MODULE_GRAPH_SVG === "1") {
  rmSync("output/architecture/module-graph.svg", { force: true });
  console.log("Generated output/architecture/module-graph.dot (whole-graph SVG skipped; use a focused module query for iteration)");
} else {
  renderDot("output/architecture/module-graph.dot", "output/architecture/module-graph.svg");
  console.log("Generated output/architecture/module-graph.dot and output/architecture/module-graph.svg");
}
