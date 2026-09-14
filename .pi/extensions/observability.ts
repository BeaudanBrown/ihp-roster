import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
// The project-owned ESM module is bundled into this extension by the tooling gate.
// @ts-ignore no standalone declaration file is needed for the local script module.
import { compareOtelProfiles } from "../../e2e/profile-compare.mjs";
// The project-owned ESM module is bundled into this extension by the tooling gate.
// @ts-ignore no standalone declaration file is needed for the local script module.
import { readQuerySummary, resolveQueryArtifactDirectory } from "../../scripts/observability/query.mjs";

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
    path.resolve(root, "output/otel-browser"),
    path.resolve(root, "output/otel-summary"),
    path.resolve(root, "build/otel"),
    path.resolve(root, ".pi/tmp/observability-query"),
  ];
  if (!allowedRoots.some((allowed) => resolved === allowed || resolved.startsWith(`${allowed}${path.sep}`))) {
    throw new Error(`Refusing to read outside approved observability artifact roots: ${input}`);
  }
  if (fs.existsSync(resolved)) {
    const canonical = fs.realpathSync(resolved);
    const canonicalRoots = allowedRoots.filter(fs.existsSync).map((allowed) => fs.realpathSync(allowed));
    if (!canonicalRoots.some((allowed) => canonical === allowed || canonical.startsWith(`${allowed}${path.sep}`))) {
      throw new Error(`Refusing artifact symlink outside approved observability roots: ${input}`);
    }
    return canonical;
  }
  return resolved;
}

function readBounded(filePath: string, requestedBytes = DEFAULT_SUMMARY_BYTES): string {
  const requested = Number.isFinite(requestedBytes) ? requestedBytes : DEFAULT_SUMMARY_BYTES;
  const maxBytes = Math.min(64_000, Math.max(1_000, Math.floor(requested)));
  const stat = fs.statSync(filePath);
  const length = Math.min(stat.size, maxBytes);
  const buffer = Buffer.alloc(length);
  const descriptor = fs.openSync(filePath, "r");
  try { fs.readSync(descriptor, buffer, 0, length, 0); } finally { fs.closeSync(descriptor); }
  const content = buffer.toString("utf8");
  return stat.size <= maxBytes ? content : `${content}\n\n[truncated ${stat.size - maxBytes} bytes]`;
}

function readJson(filePath: string): JsonObject {
  const stat = fs.statSync(filePath);
  if (!stat.isFile()) throw new Error(`Artifact is not a regular file: ${filePath}`);
  if (stat.size > 64 * 1024 * 1024) throw new Error(`Artifact exceeds 67108864 byte limit (${stat.size} bytes)`);
  try { return JSON.parse(fs.readFileSync(filePath, "utf8")); }
  catch (error: any) { throw new Error(`Malformed artifact JSON: ${error.message}`); }
}

function commonSummary(runDir: string, allowSuite = false): JsonObject {
  const productionDirectory = resolveQueryArtifactDirectory(runDir);
  const summaryPath = resolveArtifactPath(path.join(runDir, "otel-summary.json"));
  const report = productionDirectory
    ? readQuerySummary(productionDirectory)
    : readJson(summaryPath);
  const allowedSchemas = allowSuite ? ["bepis.otel.profile.v2", "bepis.otel.suite.v2"] : ["bepis.otel.profile.v2"];
  if (!allowedSchemas.includes(report.schemaVersion)) throw new Error(`Unsupported OpenTelemetry summary schema: ${report.schemaVersion || "missing"}`);
  return report;
}

function findRunDir(input?: string): string {
  if (input) return resolveQueryArtifactDirectory(input) || resolveArtifactPath(input);
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
      const productionDirectory = params.runDir ? resolveQueryArtifactDirectory(params.runDir) : null;
      if (productionDirectory) readQuerySummary(productionDirectory);
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
      const summary = commonSummary(runDir);
      const limit = Math.min(100, Math.max(1, params.limit || 20));
      return text(JSON.stringify({
        summary: summary.summary,
        spanGroups: (summary.spanGroups || []).slice(0, limit),
        categories: (summary.categories || []).slice(0, limit),
        slowestSpans: (summary.slowestSpans || []).slice(0, limit),
        largestComponents: (summary.largestComponents || []).slice(0, limit),
        responseSizes: (summary.responseSizes || []).slice(0, limit),
        renderCounters: (summary.renderCounters || []).slice(0, limit),
      }, null, 2), { runDir });
    },
  });

  pi.registerTool({
    name: "otel_trace_get",
    label: "Inspect OTel trace",
    description: "Inspect a representative safe trace view from the common otel-summary.json model.",
    parameters: Type.Object({
      runDir: Type.Optional(Type.String({ description: "artifact directory containing otel-summary.json" })),
      traceId: Type.String({ description: "trace id" }),
      spanLimit: Type.Optional(Type.Number({ default: DEFAULT_TRACE_SPAN_LIMIT })),
    }),
    async execute(_toolCallId, params) {
      const runDir = findRunDir(params.runDir);
      const report = commonSummary(runDir);
      const limit = Math.min(200, Math.max(1, params.spanLimit || DEFAULT_TRACE_SPAN_LIMIT));
      const trace = (report.traceViews || []).find((row: JsonObject) => row.traceId === params.traceId);
      const spans = (trace?.spans || []).slice(0, limit);
      return text(JSON.stringify({ traceId: params.traceId, spanCount: spans.length, totalSpanCount: trace?.spanCount || 0, spans }, null, 2), { runDir });
    },
  });

  pi.registerTool({
    name: "otel_recent",
    label: "Query recent traces",
    description: "Materialize a short, bounded, privacy-safe Tempo window. Defaults to the current local development workspace; set target=production for the configured tailnet backend.",
    parameters: Type.Object({
      target: Type.Optional(Type.Union([Type.Literal("development"), Type.Literal("production")], { default: "development" })),
      minutes: Type.Optional(Type.Number({ default: 5, minimum: 1, maximum: 15, description: "window length, 1..15 minutes" })),
      limit: Type.Optional(Type.Number({ default: 10, minimum: 1, maximum: 20, description: "trace limit, 1..20" })),
      end: Type.Optional(Type.String({ description: "optional ISO-8601 window end within seven days" })),
    }),
    async execute(_toolCallId, params) {
      const args = ["./bin/in-env", "otel-recent", `--target=${params.target ?? "development"}`, `--minutes=${params.minutes ?? 5}`, `--limit=${params.limit ?? 10}`];
      if (params.end) args.push(`--end=${params.end}`);
      const result = await runCommand("bash", args, 30_000);
      return text(`exit=${result.code}\n${result.output.slice(-40_000)}`);
    },
  });

  pi.registerTool({
    name: "otel_trace",
    label: "Inspect queried trace artifact",
    description: "Inspect one safe trace reference from a bounded development or production OTel artifact without another backend query.",
    parameters: Type.Object({
      artifactDir: Type.String({ description: ".pi/tmp/observability-query artifact directory" }),
      traceRef: Type.String({ description: "32-character safe trace reference" }),
      spanLimit: Type.Optional(Type.Number({ default: DEFAULT_TRACE_SPAN_LIMIT, minimum: 1, maximum: 200 })),
    }),
    async execute(_toolCallId, params) {
      const artifactDir = resolveQueryArtifactDirectory(params.artifactDir) || resolveArtifactPath(params.artifactDir);
      const result = await runCommand("bash", ["./bin/in-env", "otel-trace", `--artifact-dir=${artifactDir}`, `--trace-ref=${params.traceRef}`, `--span-limit=${params.spanLimit ?? DEFAULT_TRACE_SPAN_LIMIT}`], 10_000);
      return text(`exit=${result.code}\n${result.output.slice(-40_000)}`, { artifactDir });
    },
  });

  pi.registerTool({
    name: "otel_logs",
    label: "Query related logs",
    description: "Query only the fixed Loki service selector for a safe trace artifact's bounded time window and persist redacted aggregates.",
    parameters: Type.Object({
      artifactDir: Type.String({ description: ".pi/tmp/observability-query artifact directory" }),
      traceRef: Type.String({ description: "32-character safe trace reference" }),
    }),
    async execute(_toolCallId, params) {
      const artifactDir = resolveQueryArtifactDirectory(params.artifactDir) || resolveArtifactPath(params.artifactDir);
      const result = await runCommand("bash", ["./bin/in-env", "otel-logs", `--artifact-dir=${artifactDir}`, `--trace-ref=${params.traceRef}`], 30_000);
      return text(`exit=${result.code}\n${result.output.slice(-40_000)}`, { artifactDir });
    },
  });

  pi.registerTool({
    name: "otel_compare",
    label: "Compare telemetry windows",
    description: "Query and compare two short development or production Tempo windows using the common bounded comparison model.",
    parameters: Type.Object({
      target: Type.Optional(Type.Union([Type.Literal("development"), Type.Literal("production")], { default: "development" })),
      beforeEnd: Type.String({ description: "ISO-8601 end of baseline window" }),
      afterEnd: Type.String({ description: "ISO-8601 end of candidate window" }),
      minutes: Type.Optional(Type.Number({ default: 5, minimum: 1, maximum: 15, description: "each window length, 1..15 minutes" })),
      limit: Type.Optional(Type.Number({ default: 10, minimum: 1, maximum: 20, description: "trace limit per window, 1..20" })),
    }),
    async execute(_toolCallId, params) {
      const result = await runCommand("bash", ["./bin/in-env", "otel-compare", `--target=${params.target ?? "development"}`, `--before-end=${params.beforeEnd}`, `--after-end=${params.afterEnd}`, `--minutes=${params.minutes ?? 5}`, `--limit=${params.limit ?? 10}`], 60_000);
      return text(`exit=${result.code}\n${result.output.slice(-40_000)}`);
    },
  });

  pi.registerTool({
    name: "otel_compare_runs",
    label: "Compare OTel runs",
    description: "Compare matched route/span groups from two common OpenTelemetry summaries with bounded deltas and context.",
    parameters: Type.Object({
      beforeDir: Type.String({ description: "baseline artifact directory" }),
      afterDir: Type.String({ description: "candidate artifact directory" }),
      limit: Type.Optional(Type.Number({ default: 20 })),
    }),
    async execute(_toolCallId, params) {
      const beforeDir = resolveQueryArtifactDirectory(params.beforeDir) || resolveArtifactPath(params.beforeDir);
      const afterDir = resolveQueryArtifactDirectory(params.afterDir) || resolveArtifactPath(params.afterDir);
      const before = commonSummary(beforeDir, true);
      const after = commonSummary(afterDir, true);
      const limit = Math.min(100, Math.max(1, params.limit || 20));
      const comparison = compareOtelProfiles(before, after);
      const report = {
        ...comparison,
        context: { ...comparison.context, returnedSpanGroups: Math.min(limit, comparison.spans.length) },
        spans: comparison.spans.slice(0, limit),
        routes: comparison.routes.slice(0, limit),
      };
      return text(JSON.stringify(report, null, 2), { beforeDir, afterDir });
    },
  });
}
