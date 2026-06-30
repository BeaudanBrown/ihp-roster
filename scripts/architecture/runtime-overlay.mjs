import fs from "node:fs";
import path from "node:path";
import { dotId, dotQuote, maybeReadJsonFile, outputDir, renderDot, repoRoot, writeJson, writeText } from "./shared.mjs";
import "./facts.mjs";

const runDir = process.argv[2] || "output/profile-load/latest";
const summaryPath = path.join(repoRoot, runDir, "otel-summary.json");
if (!fs.existsSync(summaryPath)) {
  throw new Error(`Missing OpenTelemetry summary: ${summaryPath}`);
}
const summary = JSON.parse(fs.readFileSync(summaryPath, "utf8"));
const facts = maybeReadJsonFile("output/architecture/facts.json");
const slowest = (summary.slowestSpans || []).slice(0, 30);
const counters = (summary.renderCounters || []).slice(0, 30);
const overlay = { runDir, summary: summary.summary, slowestSpans: slowest, renderCounters: counters };
writeJson("output/architecture/runtime-overlay.json", overlay);

const lines = [
  "digraph web_map_runtime {",
  "  graph [rankdir=LR, overlap=false, splines=true];",
  "  node [shape=box, fontsize=10];",
  "  edge [fontsize=9];",
  `  run [label=${dotQuote(`OTel run\\n${runDir}`)}, shape=oval, fillcolor=\"#fff7e6\", style=filled];`,
];
for (const span of slowest) {
  const duration = span.durationMs ?? span.duration ?? "?";
  const label = `${span.name || span.spanName || "span"}\\n${duration}ms`;
  const id = dotId(`span_${span.name || span.spanName || JSON.stringify(span).slice(0, 20)}`);
  lines.push(`  ${id} [label=${dotQuote(label)}, fillcolor=\"#fff0f0\", style=filled];`);
  lines.push(`  run -> ${id};`);
}
for (const counter of counters) {
  const label = `${counter.component || counter.name || "component"}\\n${counter.count ?? counter.value ?? "?"}`;
  const id = dotId(`counter_${counter.component || counter.name || JSON.stringify(counter).slice(0, 20)}`);
  lines.push(`  ${id} [label=${dotQuote(label)}, fillcolor=\"#eef7ff\", style=filled];`);
  lines.push(`  run -> ${id} [label=\"render\"];`);
}
if (facts) {
  lines.push(`  facts [label=${dotQuote(`architecture facts\\n${facts.web.controllers.length} controllers\\n${facts.schema.tables.length} tables`)}, shape=folder, fillcolor=\"#edf7ed\", style=filled];`);
  lines.push("  facts -> run [style=dashed, label=\"overlay\"];");
}
lines.push("}");
writeText("output/architecture/web-map-runtime.dot", `${lines.join("\n")}\n`);
renderDot("output/architecture/web-map-runtime.dot", "output/architecture/web-map-runtime.svg");
console.log("Generated output/architecture/runtime-overlay.json and output/architecture/web-map-runtime.svg");
