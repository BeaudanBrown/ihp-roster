import fs from "node:fs";
import path from "node:path";
import { architectureResult, dotId, dotQuote, ensureDir, readStdinJson, renderDot, repoRoot, slug, traceDir, writeText } from "./shared.mjs";
import { OTEL_ARTIFACT_SCHEMA, resolveAllowedArtifact } from "../../e2e/otel-artifact.mjs";
import { readQuerySummary, resolveQueryArtifactDirectory } from "../observability/query.mjs";

const spanIdOf = (span) => span.spanId;
const parentIdOf = (span) => span.parentSpanId;
const durationMs = (span) => span.durationMs;

const payload = readStdinJson();
const args = payload.args || {};
const runDir = args.runDir || "output/profile-load/latest";
const traceId = args.traceId;
const limit = Number(args.limit ?? 80);
if (!traceId) throw new Error("traceId is required");
if (!Number.isInteger(limit) || limit < 1 || limit > 200) throw new Error("limit must be an integer from 1 to 200");
const requestedRunDir = path.resolve(repoRoot, runDir);
const productionRunDir = resolveQueryArtifactDirectory(requestedRunDir, { root: repoRoot });
const summaryPath = productionRunDir
  ? path.join(productionRunDir, "otel-summary.json")
  : resolveAllowedArtifact(path.join(runDir, "otel-summary.json"), { root: repoRoot });
if (!productionRunDir) {
  if (!fs.existsSync(summaryPath)) throw new Error(`Missing common OpenTelemetry summary: ${summaryPath}; run otel-profile-summary first`);
  const stat = fs.statSync(summaryPath);
  if (stat.size > 64 * 1024 * 1024) throw new Error(`OpenTelemetry summary exceeds 67108864 byte limit (${stat.size} bytes)`);
}
let report;
try {
  report = productionRunDir
    ? readQuerySummary(productionRunDir)
    : JSON.parse(fs.readFileSync(summaryPath, "utf8"));
}
catch (error) { throw new Error(`Malformed or unsafe OpenTelemetry summary: ${error.message}`); }
if (report.schemaVersion !== OTEL_ARTIFACT_SCHEMA) throw new Error(`Unsupported OpenTelemetry summary schema: ${report.schemaVersion || "missing"}`);
const traceView = (report.traceViews || []).find((trace) => trace.traceId === traceId);
const allTraceSpans = traceView?.spans || [];
const spans = allTraceSpans.slice(0, limit);
if (spans.length === 0) throw new Error(`No spans found for traceId ${traceId} in ${summaryPath}`);
const bepisSpans = spans.filter((span) => span.action);
const stem = `trace-${slug(traceId)}`;
const dotRel = `.pi/tmp/architecture-trace/${stem}.dot`;
const svgRel = `.pi/tmp/architecture-trace/${stem}.svg`;
ensureDir(traceDir);
const lines = [
  "digraph trace_diagram {",
  "  graph [rankdir=TB, overlap=false, splines=true];",
  "  node [shape=box, fontsize=10];",
  "  edge [fontsize=9];",
  `  trace [label=${dotQuote(`trace\n${traceId}`)}, shape=oval, fillcolor="#eef7ff", style=filled];`,
];
const byId = new Map(spans.map((span) => [spanIdOf(span), span]));
for (const span of spans) {
  const id = dotId(`span_${spanIdOf(span)}`);
  const name = span.name || span.spanName || spanAttr(span, "code.function") || "span";
  const duration = durationMs(span);
  const route = span.route || "";
  const bepisAction = span.action || "";
  const bepisKind = span.category || "";
  const label = [
    name,
    duration !== undefined ? `${duration}ms` : "",
    route,
    bepisAction ? `bepis: ${bepisAction}${bepisKind ? ` (${bepisKind})` : ""}` : "",
  ].filter(Boolean).join("\n");
  const fill = bepisAction ? "#e8f8ee" : route ? "#eef7ff" : "#fff7e6";
  lines.push(`  ${id} [label=${dotQuote(label)}, fillcolor=${dotQuote(fill)}, style=filled];`);
  const parent = parentIdOf(span);
  if (parent && byId.has(parent)) lines.push(`  ${dotId(`span_${parent}`)} -> ${id};`);
  else lines.push(`  trace -> ${id};`);
}
lines.push("}");
writeText(dotRel, `${lines.join("\n")}\n`);
renderDot(dotRel, svgRel);
architectureResult(`Generated trace diagram for ${traceId} with ${bepisSpans.length} Bepis-attributed spans.`, [
  { path: svgRel, kind: "diagram", language: "svg" },
  { path: dotRel, kind: "source", language: "dot" },
], { runDir, traceId, spanCount: spans.length, totalTraceSpanCount: allTraceSpans.length }, {
  metrics: {
    spans: spans.length,
    totalTraceSpans: allTraceSpans.length,
    omittedSpans: Math.max(0, allTraceSpans.length - spans.length),
    bepisAttributedSpans: bepisSpans.length,
  },
  tables: [
    {
      title: "Bepis trace attributes",
      rows: bepisSpans.map((span) => ({
        span: span.name || "span",
        durationMs: durationMs(span),
        ihpAction: span.action || "",
        bepisAction: span.action || "",
        kind: span.category || "",
        status: span.status || "",
        exclusiveMs: span.exclusiveMs,
      })),
    },
  ],
});
