#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { buildOtelSummary } from './otel-artifact.mjs';

function usage() { console.log('Usage: node e2e/otel-profile-summary.mjs <otel-traces.json> <output-dir> [metadata.json]'); }
function readJsonIfExists(filePath) { return filePath && fs.existsSync(filePath) ? JSON.parse(fs.readFileSync(path.resolve(filePath), 'utf8')) : null; }
function round(value) { return Math.round(value * 10) / 10; }
function formatBytes(bytes) { return bytes >= 1024 * 1024 ? `${round(bytes / 1024 / 1024)} MiB` : bytes >= 1024 ? `${round(bytes / 1024)} KiB` : `${round(bytes)} B`; }

export function renderOtelSummaryMarkdown(report, inputPath) {
    return `${[
        '# OpenTelemetry Profile Summary', '',
        `Schema: \`${report.schemaVersion}\``, `Trace export: \`${inputPath}\``, `Traces: ${report.summary.traceCount}`, `Spans: ${report.summary.spanCount}`,
        `Statuses: ${report.summary.statuses.ok} ok, ${report.summary.statuses.ihpResponseExit} IHP response exits, ${report.summary.statuses.error} real failures`, '',
        '## Matched Span Groups', '', '| Route/action | Span | Samples | Median | P95 | Exclusive P95 | Status |', '| --- | --- | ---: | ---: | ---: | ---: | --- |',
        ...report.spanGroups.slice(0, 30).map((row) => `| \`${row.route || row.action}\` | \`${row.span}\` | ${row.durationMs.sampleCount} | ${row.durationMs.median}ms | ${row.durationMs.p95}ms | ${row.exclusiveMs.p95}ms | ${row.statuses.error} errors / ${row.statuses.ihpResponseExit} exits |`), '',
        '## Categories', '', '| Category | Samples | Total | P95 | Exclusive P95 |', '| --- | ---: | ---: | ---: | ---: |',
        ...report.categories.map((row) => `| ${row.category} | ${row.durationMs.sampleCount} | ${row.durationMs.total}ms | ${row.durationMs.p95}ms | ${row.exclusiveMs.p95}ms |`), '',
        '## Largest HTML Components', '', '| Trace | Component | Route | Bytes | Duration |', '| --- | --- | --- | ---: | ---: |',
        ...report.largestComponents.slice(0, 20).map((span) => `| \`${span.traceId}\` | \`${span.name}\` | \`${span.route}\` | ${formatBytes(span.bytes)} | ${span.durationMs}ms |`), '',
        '## Largest Render Counters', '', '| Trace | Span | Counter | Value |', '| --- | --- | --- | ---: |',
        ...report.renderCounters.slice(0, 40).map((row) => `| \`${row.traceId}\` | \`${row.name}\` | \`${row.counter}\` | ${row.value} |`), '',
    ].join('\n')}\n`;
}

function main() {
    const [inputArg, outputDirArg, metadataArg] = process.argv.slice(2);
    if (!inputArg || !outputDirArg) { usage(); process.exit(1); }
    const inputPath = path.resolve(inputArg); const outputDir = path.resolve(outputDirArg);
    if (!fs.existsSync(inputPath)) throw new Error(`Missing OpenTelemetry trace export: ${inputPath}`);
    fs.mkdirSync(outputDir, { recursive: true });
    const report = buildOtelSummary(inputPath, { metadata: readJsonIfExists(metadataArg) });
    fs.writeFileSync(path.join(outputDir, 'otel-summary.json'), `${JSON.stringify(report, null, 2)}\n`);
    fs.writeFileSync(path.join(outputDir, 'otel-summary.md'), renderOtelSummaryMarkdown(report, inputPath));
    console.log(`OpenTelemetry profile summary: ${path.join(outputDir, 'otel-summary.md')}`);
}

if (import.meta.url === `file://${process.argv[1]}`) main();
