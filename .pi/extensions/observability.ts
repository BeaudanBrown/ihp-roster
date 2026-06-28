import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const DEFAULT_SUMMARY_BYTES = 12_000;
const DEFAULT_TRACE_SPAN_LIMIT = 80;

type JsonObject = Record<string, any>;

function text(content: string, details: JsonObject = {}) {
  return { content: [{ type: "text" as const, text: content }], details };
}

function resolveArtifactPath(input: string): string {
  const root = process.cwd();
  const resolved = path.resolve(root, input);
  const allowedRoots = [
    path.resolve(root, "output/profile-load"),
    path.resolve(root, "output/profile-load-suite"),
    path.resolve(root, "build/otel"),
  ];
  if (!allowedRoots.some((allowed) => resolved === allowed || resolved.startsWith(`${allowed}${path.sep}`))) {
    throw new Error(`Refusing to read outside profile artifact roots: ${input}`);
  }
  return resolved;
}

function readBounded(filePath: string, maxBytes = DEFAULT_SUMMARY_BYTES): string {
  const content = fs.readFileSync(filePath, "utf8");
  if (content.length <= maxBytes) return content;
  return `${content.slice(0, maxBytes)}\n\n[truncated ${content.length - maxBytes} bytes]`;
}

function readJson(filePath: string): JsonObject {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function findRunDir(input?: string): string {
  if (input) return resolveArtifactPath(input);
  return resolveArtifactPath("output/profile-load/latest");
}

function runCommand(command: string, args: string[], timeoutMs: number): Promise<{ code: number | null; output: string }> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd: process.cwd(), env: process.env, stdio: ["ignore", "pipe", "pipe"] });
    let output = "";
    const append = (chunk: Buffer) => {
      output += chunk.toString();
      if (output.length > 60_000) output = `${output.slice(0, 60_000)}\n[output truncated]\n`;
    };
    child.stdout.on("data", append);
    child.stderr.on("data", append);
    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      reject(new Error(`Command timed out after ${timeoutMs}ms`));
    }, timeoutMs);
    child.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      resolve({ code, output });
    });
  });
}

function otelValue(value: JsonObject = {}) {
  if ("stringValue" in value) return value.stringValue;
  if ("intValue" in value) return Number(value.intValue);
  if ("doubleValue" in value) return Number(value.doubleValue);
  if ("boolValue" in value) return Boolean(value.boolValue);
  if ("arrayValue" in value) return (value.arrayValue.values || []).map(otelValue);
  return null;
}

function attrsToObject(attributes: JsonObject[] = []): JsonObject {
  return Object.fromEntries(attributes.map((attr) => [attr.key, otelValue(attr.value || {})]));
}

function spanDurationMs(span: JsonObject): number {
  const start = BigInt(span.startTimeUnixNano || 0);
  const end = BigInt(span.endTimeUnixNano || 0);
  if (end <= start) return 0;
  return Math.round(Number(end - start) / 100_000) / 10;
}

function parseTraceDocuments(filePath: string): JsonObject[] {
  const content = fs.readFileSync(filePath, "utf8").trim();
  if (!content) return [];
  try {
    const parsed = JSON.parse(content);
    return Array.isArray(parsed) ? parsed : [parsed];
  } catch (_error) {
    return content.split("\n").filter(Boolean).map((line) => JSON.parse(line));
  }
}

function flattenSpans(filePath: string): JsonObject[] {
  const spans: JsonObject[] = [];
  for (const document of parseTraceDocuments(filePath)) {
    for (const resourceSpan of document.resourceSpans || []) {
      const resource = attrsToObject(resourceSpan.resource?.attributes || []);
      for (const scopeSpan of resourceSpan.scopeSpans || []) {
        for (const span of scopeSpan.spans || []) {
          spans.push({
            traceId: span.traceId,
            spanId: span.spanId,
            parentSpanId: span.parentSpanId || "",
            name: span.name,
            durationMs: spanDurationMs(span),
            attributes: attrsToObject(span.attributes || []),
            resource,
          });
        }
      }
    }
  }
  return spans;
}

export default function observabilityExtension(pi: ExtensionAPI) {
  pi.registerTool({
    name: "roster_profile_run",
    label: "Run roster profile",
    description: "Run a safe low-rate local profile-load scenario with OpenTelemetry artifacts.",
    parameters: Type.Object({
      scenario: Type.Optional(Type.String({ description: "profile-load scenario", default: "roster-wide" })),
      rate: Type.Optional(Type.Number({ description: "iterations/sec", default: 1 })),
      duration: Type.Optional(Type.String({ description: "k6 duration", default: "5s" })),
      vus: Type.Optional(Type.Number({ description: "preallocated VUs", default: 1 })),
      outputDir: Type.Optional(Type.String({ description: "optional output/profile-load/... directory" })),
      timeoutMs: Type.Optional(Type.Number({ description: "command timeout", default: 240000 })),
    }),
    async execute(_toolCallId, params) {
      const scenario = params.scenario || "roster-wide";
      const rate = String(params.rate || 1);
      const duration = params.duration || "5s";
      const vus = String(params.vus || 1);
      const args = ["./bin/in-env", "profile-load", `--scenario=${scenario}`, `--rate=${rate}`, `--duration=${duration}`, `--vus=${vus}`, "--otel"];
      if (params.outputDir) args.push(`--output-dir=${params.outputDir}`);
      const result = await runCommand("bash", args, params.timeoutMs || 240_000);
      const outputDirMatch = result.output.match(/Profile load artifacts: (.+)/g)?.at(-1)?.replace("Profile load artifacts: ", "").trim();
      const summaryPath = outputDirMatch ? path.join(outputDirMatch, "otel-summary.md") : "";
      const summary = summaryPath && fs.existsSync(summaryPath) ? readBounded(summaryPath) : "No otel-summary.md produced.";
      return text(`exit=${result.code}\n${result.output.slice(-4000)}\n\n${summary}`, { outputDir: outputDirMatch, summaryPath });
    },
  });

  pi.registerTool({
    name: "roster_profile_summary",
    label: "Read profile summary",
    description: "Read bounded k6 and OpenTelemetry profile summaries from an artifact directory.",
    parameters: Type.Object({
      runDir: Type.Optional(Type.String({ description: "output/profile-load/... or output/profile-load-suite/... (default latest profile-load)" })),
      maxBytes: Type.Optional(Type.Number({ default: DEFAULT_SUMMARY_BYTES })),
    }),
    async execute(_toolCallId, params) {
      const runDir = findRunDir(params.runDir);
      const files = ["suite-summary.md", "load-profile.md", "otel-summary.md"].filter((name) => fs.existsSync(path.join(runDir, name)));
      const body = files.map((name) => `## ${name}\n\n${readBounded(path.join(runDir, name), params.maxBytes || DEFAULT_SUMMARY_BYTES)}`).join("\n\n");
      return text(body || `No known summary files found in ${runDir}`, { runDir, files });
    },
  });

  pi.registerTool({
    name: "otel_trace_search",
    label: "Search OTel traces",
    description: "Return bounded slow span/component/counter rows from otel-summary.json.",
    parameters: Type.Object({
      runDir: Type.Optional(Type.String({ description: "artifact directory containing otel-summary.json" })),
      limit: Type.Optional(Type.Number({ default: 20 })),
    }),
    async execute(_toolCallId, params) {
      const runDir = findRunDir(params.runDir);
      const summary = readJson(path.join(runDir, "otel-summary.json"));
      const limit = params.limit || 20;
      return text(JSON.stringify({
        summary: summary.summary,
        slowestSpans: (summary.slowestSpans || []).slice(0, limit),
        largestComponents: (summary.largestComponents || []).slice(0, limit),
        renderCounters: (summary.renderCounters || []).slice(0, limit),
      }, null, 2), { runDir });
    },
  });

  pi.registerTool({
    name: "otel_trace_get",
    label: "Inspect OTel trace",
    description: "Inspect a representative trace from otel-traces.json with bounded spans.",
    parameters: Type.Object({
      runDir: Type.Optional(Type.String({ description: "artifact directory containing otel-traces.json" })),
      traceId: Type.String({ description: "trace id" }),
      spanLimit: Type.Optional(Type.Number({ default: DEFAULT_TRACE_SPAN_LIMIT })),
    }),
    async execute(_toolCallId, params) {
      const runDir = findRunDir(params.runDir);
      const spans = flattenSpans(path.join(runDir, "otel-traces.json"))
        .filter((span) => span.traceId === params.traceId)
        .sort((a, b) => b.durationMs - a.durationMs)
        .slice(0, params.spanLimit || DEFAULT_TRACE_SPAN_LIMIT);
      return text(JSON.stringify({ traceId: params.traceId, spanCount: spans.length, spans }, null, 2), { runDir });
    },
  });

  pi.registerTool({
    name: "otel_compare_runs",
    label: "Compare OTel runs",
    description: "Compare two otel-summary.json artifacts with bounded slow span/component/counter deltas.",
    parameters: Type.Object({
      beforeDir: Type.String({ description: "baseline artifact directory" }),
      afterDir: Type.String({ description: "candidate artifact directory" }),
      limit: Type.Optional(Type.Number({ default: 20 })),
    }),
    async execute(_toolCallId, params) {
      const beforeDir = resolveArtifactPath(params.beforeDir);
      const afterDir = resolveArtifactPath(params.afterDir);
      const before = readJson(path.join(beforeDir, "otel-summary.json"));
      const after = readJson(path.join(afterDir, "otel-summary.json"));
      const limit = params.limit || 20;
      const report = {
        before: before.summary,
        after: after.summary,
        afterSlowestSpans: (after.slowestSpans || []).slice(0, limit),
        afterLargestComponents: (after.largestComponents || []).slice(0, limit),
        afterLargestCounters: (after.renderCounters || []).slice(0, limit),
      };
      return text(JSON.stringify(report, null, 2), { beforeDir, afterDir });
    },
  });
}
