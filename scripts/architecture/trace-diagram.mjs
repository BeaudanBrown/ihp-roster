import fs from "node:fs";
import path from "node:path";
import { architectureResult, dotId, dotQuote, ensureDir, readStdinJson, renderDot, repoRoot, slug, traceDir, writeText } from "./shared.mjs";

function parsePossiblyConcatenatedJson(content) {
  const trimmed = content.trim();
  if (!trimmed) return [];
  try {
    const parsed = JSON.parse(trimmed);
    return Array.isArray(parsed) ? parsed : [parsed];
  } catch (_error) {
    return trimmed.split("\n").filter(Boolean).map((line) => JSON.parse(line));
  }
}

function otelValue(value = {}) {
  if ("stringValue" in value) return value.stringValue;
  if ("intValue" in value) return Number(value.intValue);
  if ("doubleValue" in value) return Number(value.doubleValue);
  if ("boolValue" in value) return Boolean(value.boolValue);
  if ("arrayValue" in value) return value.arrayValue.values?.map(otelValue) || [];
  return null;
}

function attrsToObject(attributes = []) {
  if (!Array.isArray(attributes)) return attributes || {};
  return Object.fromEntries(attributes.map((attr) => [attr.key, otelValue(attr.value || {})]));
}

function flattenTraces(value, spans = [], inherited = {}) {
  if (Array.isArray(value)) {
    for (const item of value) flattenTraces(item, spans, inherited);
    return spans;
  }
  if (!value || typeof value !== "object") return spans;

  const resource = value.resource?.attributes ? { ...(inherited.resource || {}), ...attrsToObject(value.resource.attributes) } : inherited.resource;
  const scope = value.scope ? { ...(inherited.scope || {}), name: value.scope.name || "", version: value.scope.version || "" } : inherited.scope;
  const nextInherited = { resource, scope };

  if (value.traceId || value.trace_id || value.spanId || value.span_id) {
    spans.push({ ...value, resource: resource || value.resource || {}, scope: scope || value.scope || {} });
  }
  for (const key of ["spans", "resourceSpans", "scopeSpans", "instrumentationLibrarySpans"]) {
    if (value[key]) flattenTraces(value[key], spans, nextInherited);
  }
  return spans;
}

function spanAttributes(span) {
  return attrsToObject(span.attributes || {});
}

function spanAttr(span, name) {
  const attrs = spanAttributes(span);
  if (name in attrs) return attrs[name];
  const resourceAttrs = attrsToObject(span.resource?.attributes || span.resource || {});
  return resourceAttrs[name];
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
const documents = parsePossiblyConcatenatedJson(fs.readFileSync(tracesPath, "utf8"));
const allTraceSpans = flattenTraces(documents).filter((span) => traceIdOf(span) === traceId);
const spans = allTraceSpans.slice(0, limit);
if (spans.length === 0) throw new Error(`No spans found for traceId ${traceId} in ${tracesPath}`);
const bepisSpans = spans.filter((span) => spanAttr(span, "bepis.action") || spanAttr(span, "bepis.ihp.action") || spanAttr(span, "bepis.action.kind"));
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
  const route = spanAttr(span, "http.route") || spanAttr(span, "url.path") || spanAttr(span, "http.target") || "";
  const bepisAction = spanAttr(span, "bepis.action");
  const bepisKind = spanAttr(span, "bepis.action.kind");
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
        ihpAction: spanAttr(span, "bepis.ihp.action") || "",
        bepisAction: spanAttr(span, "bepis.action") || "",
        kind: spanAttr(span, "bepis.action.kind") || "",
        responseKinds: spanAttr(span, "bepis.response.kinds") || "",
        auditPolicy: spanAttr(span, "bepis.mutation.audit_policy") || "",
        realtimePolicy: spanAttr(span, "bepis.mutation.realtime_policy") || "",
        scopePolicy: spanAttr(span, "bepis.mutation.scope_policy") || "",
      })),
    },
  ],
});
