#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { OTEL_ARTIFACT_SCHEMA, readBoundedJsonArtifact, resolveAllowedArtifact } from './otel-artifact.mjs';

function usage() {
  console.log('Usage: node e2e/otel-suite-summary.mjs <suite-output-dir> <scenario-name>...');
}
function round(value) { return Math.round(value * 10) / 10; }
function formatBytes(bytes) {
  if (!Number.isFinite(bytes)) return '?';
  if (bytes >= 1024 * 1024) return `${round(bytes / (1024 * 1024))} MiB`;
  if (bytes >= 1024) return `${round(bytes / 1024)} KiB`;
  return `${round(bytes)} B`;
}
function readProfileSummary(filePath) {
  const report = readBoundedJsonArtifact(filePath);
  if (report.schemaVersion !== OTEL_ARTIFACT_SCHEMA) throw new Error(`Unsupported OpenTelemetry summary schema: ${report.schemaVersion || 'missing'}`);
  return report;
}

function main() {
  const [suiteDirArg, ...scenarios] = process.argv.slice(2);
  if (!suiteDirArg || scenarios.length === 0) {
    usage();
    process.exit(1);
  }
  const suiteDir = resolveAllowedArtifact(suiteDirArg);
  if (scenarios.length > 20) throw new Error(`OpenTelemetry suite exceeds 20 scenario limit (${scenarios.length})`);
  const reports = scenarios.flatMap((scenario) => {
    if (!/^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$/.test(scenario) || scenario === '..') throw new Error(`Unsafe scenario name: ${scenario.slice(0, 100)}`);
    const candidatePath = path.join(suiteDir, scenario, 'otel-summary.json');
    if (!fs.existsSync(candidatePath)) return [];
    const filePath = resolveAllowedArtifact(candidatePath);
    return [{ scenario, filePath, report: readProfileSummary(filePath) }];
  });
  const summary = {
    schemaVersion: 'bepis.otel.suite.v2',
    suiteDir,
    scenarios: reports.map(({ scenario, report }) => ({
      scenario,
      report: {
        schemaVersion: report.schemaVersion,
        context: report.context,
        summary: report.summary,
        loadPressure: report.loadPressure,
        routes: (report.routes || []).slice(0, 2_000),
        spanGroups: (report.spanGroups || []).slice(0, 2_000),
        categories: (report.categories || []).slice(0, 20),
      },
    })),
  };
  const slowestSpans = reports.flatMap(({ scenario, report }) => (report.slowestSpans || []).map((row) => ({ scenario, ...row })))
    .sort((a, b) => b.durationMs - a.durationMs);
  const largestComponents = reports.flatMap(({ scenario, report }) => (report.largestComponents || []).map((row) => ({ scenario, ...row })))
    .sort((a, b) => b.bytes - a.bytes);
  const renderCounters = reports.flatMap(({ scenario, report }) => (report.renderCounters || []).map((row) => ({ scenario, ...row })))
    .sort((a, b) => b.value - a.value);

  const lines = [
    '# OpenTelemetry Load Profile Suite',
    '',
    `Suite: \`${suiteDir}\``,
    `Scenarios with OTel summaries: ${reports.map((item) => `\`${item.scenario}\``).join(', ') || 'none'}`,
    '',
    '## Scenario Coverage',
    '',
    '| Scenario | Traces | Spans | Render counter samples | Component byte samples |',
    '| --- | ---: | ---: | ---: | ---: |',
    ...reports.map(({ scenario, report }) => `| \`${scenario}\` | ${report.summary?.traceCount || 0} | ${report.summary?.spanCount || 0} | ${report.summary?.renderCounterSampleCount || 0} | ${report.summary?.componentByteSampleCount || 0} |`),
    '',
    '## Slowest Spans',
    '',
    '| Scenario | Trace | Span | Route | Duration |',
    '| --- | --- | --- | --- | ---: |',
    ...slowestSpans.slice(0, 30).map((span) => `| \`${span.scenario}\` | \`${span.traceId}\` | \`${span.name}\` | \`${span.route}\` | ${span.durationMs}ms |`),
    '',
    '## Largest HTML Components',
    '',
    '| Scenario | Trace | Component | Route | Bytes | Duration |',
    '| --- | --- | --- | --- | ---: | ---: |',
    ...largestComponents.slice(0, 30).map((span) => `| \`${span.scenario}\` | \`${span.traceId}\` | \`${span.name}\` | \`${span.route}\` | ${formatBytes(span.bytes)} | ${span.durationMs}ms |`),
    '',
    '## Largest Render Counters',
    '',
    '| Scenario | Trace | Span | Counter | Value |',
    '| --- | --- | --- | --- | ---: |',
    ...renderCounters.slice(0, 60).map((row) => `| \`${row.scenario}\` | \`${row.traceId}\` | \`${row.name || row.span}\` | \`${row.counter}\` | ${row.value} |`),
    '',
  ];

  const jsonOutput = `${JSON.stringify(summary, null, 2)}\n`;
  const markdownOutput = `${lines.join('\n')}\n`;
  if (Buffer.byteLength(jsonOutput) > 64 * 1024 * 1024) throw new Error(`OpenTelemetry suite summary exceeds 67108864 byte limit (${Buffer.byteLength(jsonOutput)} bytes)`);
  if (Buffer.byteLength(markdownOutput) > 64 * 1024 * 1024) throw new Error(`OpenTelemetry suite Markdown exceeds 67108864 byte limit (${Buffer.byteLength(markdownOutput)} bytes)`);
  const jsonPath = path.join(suiteDir, 'otel-summary.json');
  const markdownPath = path.join(suiteDir, 'otel-summary.md');
  for (const outputPath of [jsonPath, markdownPath]) {
    try {
      if (fs.lstatSync(outputPath).isSymbolicLink()) throw new Error(`Refusing to overwrite OpenTelemetry suite symlink: ${path.basename(outputPath)}`);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
    resolveAllowedArtifact(outputPath);
  }
  fs.writeFileSync(jsonPath, jsonOutput);
  fs.writeFileSync(markdownPath, markdownOutput);
  console.log(`OpenTelemetry suite summary: ${markdownPath}`);
}

main();
