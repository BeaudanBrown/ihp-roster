#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

function usage() {
  console.log('Usage: node e2e/otel-profile-summary.mjs <otel-traces.json> <output-dir> [metadata.json]');
}

function round(value) { return Math.round(value * 10) / 10; }
function formatBytes(bytes) {
  if (!Number.isFinite(bytes)) return '?';
  if (bytes >= 1024 * 1024) return `${round(bytes / (1024 * 1024))} MiB`;
  if (bytes >= 1024) return `${round(bytes / 1024)} KiB`;
  return `${round(bytes)} B`;
}

function readJsonIfExists(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return null;
  return JSON.parse(fs.readFileSync(path.resolve(filePath), 'utf8'));
}

function parsePossiblyConcatenatedJson(content) {
  const trimmed = content.trim();
  if (!trimmed) return [];
  try {
    const parsed = JSON.parse(trimmed);
    return Array.isArray(parsed) ? parsed : [parsed];
  } catch (_error) {
    return trimmed.split('\n').filter(Boolean).map((line) => JSON.parse(line));
  }
}

function otelValue(value = {}) {
  if ('stringValue' in value) return value.stringValue;
  if ('intValue' in value) return Number(value.intValue);
  if ('doubleValue' in value) return Number(value.doubleValue);
  if ('boolValue' in value) return Boolean(value.boolValue);
  if ('arrayValue' in value) return value.arrayValue.values?.map(otelValue) || [];
  return null;
}

function attrsToObject(attributes = []) {
  return Object.fromEntries(attributes.map((attr) => [attr.key, otelValue(attr.value || {})]));
}

function durationMs(span) {
  const start = BigInt(span.startTimeUnixNano || 0);
  const end = BigInt(span.endTimeUnixNano || 0);
  if (end <= start) return 0;
  return round(Number(end - start) / 1_000_000);
}

function flattenSpans(documents) {
  const spans = [];
  for (const document of documents) {
    const resourceSpans = document.resourceSpans || [];
    for (const resourceSpan of resourceSpans) {
      const resource = attrsToObject(resourceSpan.resource?.attributes || []);
      for (const scopeSpan of resourceSpan.scopeSpans || []) {
        const scope = scopeSpan.scope || {};
        for (const span of scopeSpan.spans || []) {
          const attributes = attrsToObject(span.attributes || []);
          const events = (span.events || []).map((event) => ({
            name: event.name,
            attributes: attrsToObject(event.attributes || []),
          }));
          spans.push({
            traceId: span.traceId,
            spanId: span.spanId,
            parentSpanId: span.parentSpanId || '',
            name: span.name,
            durationMs: durationMs(span),
            attributes,
            events,
            resource,
            scopeName: scope.name || '',
          });
        }
      }
    }
  }
  return spans;
}

function routeFor(span) {
  return span.attributes['http.route'] || span.attributes['bepis.ihp.action'] || span.attributes['http.target'] || '';
}

function summarize(spans, metadata) {
  const traceIds = new Set(spans.map((span) => span.traceId).filter(Boolean));
  const slowestSpans = [...spans]
    .sort((a, b) => b.durationMs - a.durationMs)
    .slice(0, 30)
    .map((span) => ({ traceId: span.traceId, spanId: span.spanId, parentSpanId: span.parentSpanId, name: span.name, route: routeFor(span), durationMs: span.durationMs }));
  const largestComponents = spans
    .filter((span) => Number.isFinite(Number(span.attributes['html.bytes'])))
    .sort((a, b) => Number(b.attributes['html.bytes']) - Number(a.attributes['html.bytes']))
    .slice(0, 30)
    .map((span) => ({ traceId: span.traceId, spanId: span.spanId, name: span.name, route: routeFor(span), bytes: Number(span.attributes['html.bytes']), durationMs: span.durationMs }));
  const renderCounters = [];
  for (const span of spans) {
    for (const [key, value] of Object.entries(span.attributes)) {
      if (key.startsWith('render.roster.')) {
        renderCounters.push({ traceId: span.traceId, spanId: span.spanId, span: span.name, route: routeFor(span), counter: key, value: Number(value) });
      }
    }
  }
  renderCounters.sort((a, b) => (b.value || 0) - (a.value || 0));
  return {
    metadata,
    summary: {
      traceCount: traceIds.size,
      spanCount: spans.length,
      renderCounterSampleCount: renderCounters.length,
      componentByteSampleCount: largestComponents.length,
    },
    slowestSpans,
    largestComponents,
    renderCounters: renderCounters.slice(0, 80),
  };
}

function markdown(report, inputPath) {
  const lines = [
    '# OpenTelemetry Profile Summary',
    '',
    `Trace export: \`${inputPath}\``,
    `Traces: ${report.summary.traceCount}`,
    `Spans: ${report.summary.spanCount}`,
    '',
    '## Slowest Spans',
    '',
    '| Trace | Span | Route | Duration |',
    '| --- | --- | --- | ---: |',
    ...report.slowestSpans.slice(0, 20).map((span) => `| \`${span.traceId}\` | \`${span.name}\` | \`${span.route}\` | ${span.durationMs}ms |`),
    '',
    '## Largest HTML Components',
    '',
    '| Trace | Component | Route | Bytes | Duration |',
    '| --- | --- | --- | ---: | ---: |',
    ...report.largestComponents.slice(0, 20).map((span) => `| \`${span.traceId}\` | \`${span.name}\` | \`${span.route}\` | ${formatBytes(span.bytes)} | ${span.durationMs}ms |`),
    '',
    '## Largest Render Counters',
    '',
    '| Trace | Span | Counter | Value |',
    '| --- | --- | --- | ---: |',
    ...report.renderCounters.slice(0, 40).map((row) => `| \`${row.traceId}\` | \`${row.span}\` | \`${row.counter}\` | ${row.value} |`),
    '',
  ];
  return `${lines.join('\n')}\n`;
}

function main() {
  const [inputArg, outputDirArg, metadataArg] = process.argv.slice(2);
  if (!inputArg || !outputDirArg) {
    usage();
    process.exit(1);
  }
  const inputPath = path.resolve(inputArg);
  const outputDir = path.resolve(outputDirArg);
  if (!fs.existsSync(inputPath)) {
    console.error(`Missing OpenTelemetry trace export: ${inputPath}`);
    process.exit(1);
  }
  const documents = parsePossiblyConcatenatedJson(fs.readFileSync(inputPath, 'utf8'));
  const spans = flattenSpans(documents);
  const report = summarize(spans, readJsonIfExists(metadataArg));
  fs.writeFileSync(path.join(outputDir, 'otel-summary.json'), `${JSON.stringify(report, null, 2)}\n`);
  fs.writeFileSync(path.join(outputDir, 'otel-summary.md'), markdown(report, inputPath));
  console.log(`OpenTelemetry profile summary: ${path.join(outputDir, 'otel-summary.md')}`);
}

main();
