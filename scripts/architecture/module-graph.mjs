import { dotId, dotQuote } from "./shared.mjs";
import { generateWholeGraph } from "./whole-graph.mjs";

await generateWholeGraph("module-graph", (facts) => {
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
  return `${lines.join("\n")}\n`;
});
