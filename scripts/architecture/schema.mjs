import { dotId, dotQuote } from "./shared.mjs";
import { generateWholeGraph } from "./whole-graph.mjs";

await generateWholeGraph("schema", (facts) => {
  const lines = [
    "digraph schema {",
    "  graph [rankdir=LR, overlap=false, splines=true];",
    "  node [shape=record, fontsize=10];",
    "  edge [fontsize=9];",
  ];

  for (const table of facts.schema.tables) {
    const columns = table.columns.slice(0, 16).map((column) => `${column.name}: ${column.type}`).join("\\l");
    const suffix = table.columns.length > 16 ? "\\l…" : "";
    lines.push(`  ${dotId(table.name)} [label=${dotQuote(`{${table.name}|${columns}${suffix}\\l}`)}];`);
  }

  for (const table of facts.schema.tables) {
    for (const fk of table.foreignKeys) {
      lines.push(`  ${dotId(table.name)} -> ${dotId(fk.referencesTable)} [label=${dotQuote(fk.columns.join(", "))}];`);
    }
  }

  lines.push("}");
  return `${lines.join("\n")}\n`;
});
