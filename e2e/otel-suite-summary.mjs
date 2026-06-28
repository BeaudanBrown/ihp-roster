#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

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
function readJson(filePath) { return JSON.parse(fs.readFileSync(filePath, 'utf8')); }

function main() {
  const [suiteDirArg, ...scenarios] = process.argv.slice(2);
  if (!suiteDirArg || scenarios.length === 0) {
    usage();
    process.exit(1);
  }
  const suiteDir = path.resolve(suiteDirArg);
  const reports = scenarios.flatMap((scenario) => {
    const filePath = path.join(suiteDir, scenario, 'otel-summary.json');
    if (!fs.existsSync(filePath)) return [];
    return [{ scenario, filePath, report: readJson(filePath) }];
  });
  const summary = {
    suiteDir,
    scenarios: reports.map(({ scenario, report }) => ({
      scenario,
      summary: report.summary,
      slowestSpans: report.slowestSpans?.slice(0, 10) || [],
      largestComponents: report.largestComponents?.slice(0, 10) || [],
      renderCounters: report.renderCounters?.slice(0, 20) || [],
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
    ...renderCounters.slice(0, 60).map((row) => `| \`${row.scenario}\` | \`${row.traceId}\` | \`${row.span}\` | \`${row.counter}\` | ${row.value} |`),
    '',
  ];

  fs.writeFileSync(path.join(suiteDir, 'otel-summary.json'), `${JSON.stringify(summary, null, 2)}\n`);
  fs.writeFileSync(path.join(suiteDir, 'otel-summary.md'), `${lines.join('\n')}\n`);
  console.log(`OpenTelemetry suite summary: ${path.join(suiteDir, 'otel-summary.md')}`);
}

main();
