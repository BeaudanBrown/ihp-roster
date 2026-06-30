import fs from "node:fs";
import path from "node:path";
import { architectureResult, dotId, dotQuote, ensureDir, readStdinJson, renderDot, repoRoot, slug, traceDir, writeText } from "./shared.mjs";

function flattenTraces(value, spans = []) {
  if (Array.isArray(value)) {
    for (const item of value) flattenTraces(item, spans);
    return spans;
  }
  if (!value || typeof value !== "object") return spans;
  if (value.traceId || value.trace_id || value.spanId || value.span_id) spans.push(value);
  for (const key of ["spans", "resourceSpans", "scopeSpans", "instrumentationLibrarySpans"]) {
    if (value[key]) flattenTraces(value[key], spans);
  }
  return spans;
}

function spanAttr(span, name) {
  const attrs = span.attributes || span.resource?.attributes || [];
  if (Array.isArray(attrs)) {
    const found = attrs.find((attr) => attr.key === name);
    if (!found) return undefined;
    const value = found.value || {};
    return value.stringValue ?? value.intValue ?? value.doubleValue ?? value.boolValue;
  }
  return attrs[name];
}

function traceIdOf(span) {
  return span.traceId || span.trace_id;
}
function spanIdOf(span) {
  return span.spanId || span.span_id || span.id;
}
function parentIdOf(span) {
  return span.parentSpanId || span.parent_span_id || span.parentId;
}
function durationMs(span) {
  if (typeof span.durationMs === "number") return span.durationMs;
  const start = Number(span.startTimeUnixNano || span.start_time_unix_nano || 0);
  const end = Number(span.endTimeUnixNano || span.end_time_unix_nano || 0);
  if (start && end) return Math.round((end - start) / 1_000_000);
  return undefined;
}

const payload = readStdinJson();
const args = payload.args || {};
const runDir = args.runDir || "output/profile-load/latest";
const traceId = args.traceId;
const limit = Number(args.limit ?? 80);
const tracesPath = path.join(repoRoot, runDir, "otel-traces.json");
if (!traceId) throw new Error("traceId is required");
if (!fs.existsSync(tracesPath)) throw new Error(`Missing OpenTelemetry traces: ${tracesPath}`);
const raw = JSON.parse(fs.readFileSync(tracesPath, "utf8"));
const spans = flattenTraces(raw).filter((span) => traceIdOf(span) === traceId).slice(0, limit);
if (spans.length === 0) throw new Error(`No spans found for traceId ${traceId} in ${tracesPath}`);
const stem = `trace-${slug(traceId)}`;
const dotRel = `.pi/tmp/architecture-trace/${stem}.dot`;
const svgRel = `.pi/tmp/architecture-trace/${stem}.svg`;
ensureDir(traceDir);
const lines = [
  "digraph trace_diagram {",
  "  graph [rankdir=TB, overlap=false, splines=true];",
  "  node [shape=box, fontsize=10];",
  "  edge [fontsize=9];",
  `  trace [label=${dotQuote(`trace\n${traceId}`)}, shape=oval, fillcolor=\"#eef7ff\", style=filled];`,
];
const byId = new Map(spans.map((span) => [spanIdOf(span), span]));
for (const span of spans) {
  const id = dotId(`span_${spanIdOf(span)}`);
  const name = span.name || span.spanName || spanAttr(span, "code.function") || "span";
  const duration = durationMs(span);
  const route = spanAttr(span, "http.route") || spanAttr(span, "url.path") || "";
  lines.push(`  ${id} [label=${dotQuote(`${name}${duration !== undefined ? `\n${duration}ms` : ""}${route ? `\n${route}` : ""}`)}, fillcolor=\"#fff7e6\", style=filled];`);
  const parent = parentIdOf(span);
  if (parent && byId.has(parent)) lines.push(`  ${dotId(`span_${parent}`)} -> ${id};`);
  else lines.push(`  trace -> ${id};`);
}
lines.push("}");
writeText(dotRel, `${lines.join("\n")}\n`);
renderDot(dotRel, svgRel);
architectureResult(`Generated trace diagram for ${traceId}.`, [
  { path: svgRel, kind: "diagram", language: "svg" },
  { path: dotRel, kind: "source", language: "dot" },
], { runDir, traceId, spanCount: spans.length });
