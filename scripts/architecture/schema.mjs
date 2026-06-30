import { dotId, dotQuote, maybeReadJsonFile, renderDot, writeText } from "./shared.mjs";
import "./facts.mjs";

const facts = maybeReadJsonFile("output/architecture/facts.json");
if (!facts) throw new Error("Missing output/architecture/facts.json");

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
writeText("output/architecture/schema.dot", `${lines.join("\n")}\n`);
renderDot("output/architecture/schema.dot", "output/architecture/schema.svg");
console.log("Generated output/architecture/schema.dot and output/architecture/schema.svg");
