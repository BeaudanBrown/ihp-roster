#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const DEFAULT_TEMPO_URL = process.env.TEMPO_URL || 'http://127.0.0.1:3200';
const DEFAULT_SERVICE = process.env.OTEL_SERVICE_NAME || 'ihp-roster-dev';

function usage() {
    console.log(`Usage:
  node e2e/otel-trace-summary.mjs [options]

Options:
  --tempo-url <url>     Tempo API base URL (default: ${DEFAULT_TEMPO_URL})
  --service <name>      service.name to search (default: ${DEFAULT_SERVICE})
  --run-id <id>         Only include traces tagged with bepis.trace.run
  --limit <n>           Tempo search limit (default: 200)
  --output-dir <path>   Write traces.json, summary.json, summary.md
  --help                Show this message
`);
}

function parseArgs(argv) {
    const options = {
        tempoUrl: DEFAULT_TEMPO_URL,
        service: DEFAULT_SERVICE,
        runId: process.env.OTEL_TRACE_RUN_ID || null,
        limit: Number(process.env.OTEL_TRACE_LIMIT || '200'),
        outputDir: null,
    };
    const args = [...argv];
    if (args.includes('--help')) {
        usage();
        process.exit(0);
    }
    while (args.length > 0) {
        const arg = args.shift();
        const [flag, inlineValue] = arg.includes('=') ? arg.split(/=(.*)/s, 2) : [arg, null];
        const next = () => inlineValue ?? args.shift();
        switch (flag) {
            case '--tempo-url': options.tempoUrl = next(); break;
            case '--service': options.service = next(); break;
            case '--run-id': options.runId = next(); break;
            case '--limit': options.limit = Number(next()); break;
            case '--output-dir': options.outputDir = next(); break;
            default: throw new Error(`Unknown argument: ${arg}`);
        }
    }
    if (!options.tempoUrl) throw new Error('--tempo-url is required');
    if (!options.service) throw new Error('--service is required');
    return options;
}

async function fetchJson(url) {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`${response.status} ${response.statusText} from ${url}`);
    return response.json();
}

function attrValue(value) {
    if (!value) return null;
    if ('stringValue' in value) return value.stringValue;
    if ('intValue' in value) return Number(value.intValue);
    if ('doubleValue' in value) return Number(value.doubleValue);
    if ('boolValue' in value) return Boolean(value.boolValue);
    if ('arrayValue' in value) return value.arrayValue;
    return null;
}

function spanAttributes(span) {
    const attrs = {};
    for (const attr of span.attributes || []) {
        attrs[attr.key] = attrValue(attr.value || {});
    }
    return attrs;
}

function spanDurationMs(span) {
    const start = BigInt(span.startTimeUnixNano || 0);
    const end = BigInt(span.endTimeUnixNano || 0);
    return Number(end - start) / 1_000_000;
}

function flattenTrace(traceId, trace) {
    const spans = [];
    for (const batch of trace.batches || []) {
        const resourceAttrs = Object.fromEntries((batch.resource?.attributes || []).map((attr) => [attr.key, attrValue(attr.value || {})]));
        for (const scopeSpans of batch.scopeSpans || []) {
            for (const span of scopeSpans.spans || []) {
                const attributes = { ...resourceAttrs, ...spanAttributes(span) };
                spans.push({
                    traceId,
                    spanId: span.spanId,
                    parentSpanId: span.parentSpanId || null,
                    name: span.name,
                    durationMs: spanDurationMs(span),
                    statusCode: span.status?.code || 'STATUS_CODE_UNSET',
                    statusMessage: span.status?.message || '',
                    attributes,
                });
            }
        }
    }
    return spans;
}

function classifyError(span) {
    if (span.statusCode !== 'STATUS_CODE_ERROR') return null;
    if (/ResponseException/i.test(span.statusMessage || '')) return 'ihp_response_exit';
    return 'error';
}

function summarizeTrace(traceId, rootName, spans) {
    const byParent = new Map();
    for (const span of spans) {
        if (!span.parentSpanId) continue;
        if (!byParent.has(span.parentSpanId)) byParent.set(span.parentSpanId, []);
        byParent.get(span.parentSpanId).push(span);
    }
    const longest = [...spans].sort((a, b) => b.durationMs - a.durationMs)[0] || null;
    const root = spans.find((span) => span.name === rootName) || longest;
    const duplicates = Object.entries(spans.reduce((acc, span) => {
        acc[span.name] ||= { name: span.name, count: 0, totalMs: 0, maxMs: 0 };
        acc[span.name].count += 1;
        acc[span.name].totalMs += span.durationMs;
        acc[span.name].maxMs = Math.max(acc[span.name].maxMs, span.durationMs);
        return acc;
    }, {})).map(([, value]) => value).filter((item) => item.count > 1 && item.totalMs >= 5).sort((a, b) => b.totalMs - a.totalMs);
    const topSpans = [...spans].filter((span) => span !== root).sort((a, b) => b.durationMs - a.durationMs).slice(0, 12);
    const exclusiveTop = [...spans].map((span) => {
        const childTotalMs = (byParent.get(span.spanId) || []).reduce((sum, child) => sum + child.durationMs, 0);
        return { name: span.name, durationMs: span.durationMs, exclusiveMs: Math.max(0, span.durationMs - childTotalMs) };
    }).sort((a, b) => b.exclusiveMs - a.exclusiveMs).slice(0, 12);
    const errors = spans.filter((span) => span.statusCode === 'STATUS_CODE_ERROR').map((span) => ({
        name: span.name,
        durationMs: span.durationMs,
        statusMessage: span.statusMessage,
        classification: classifyError(span),
    }));
    const steps = [...new Set(spans.map((span) => span.attributes['bepis.trace.step']).filter(Boolean))];
    return {
        traceId,
        rootName: root?.name || rootName,
        rootDurationMs: root?.durationMs || 0,
        spanCount: spans.length,
        steps,
        errors,
        topSpans,
        exclusiveTop,
        duplicates,
    };
}

function renderMarkdown(options, summaries) {
    const lines = [];
    lines.push('# OTel Trace Summary', '');
    lines.push(`service: \`${options.service}\``);
    if (options.runId) lines.push(`run: \`${options.runId}\``);
    lines.push('');
    if (summaries.length === 0) {
        lines.push('No traces matched. If this was a browser diagnostic run, restart the dev server with `IHP_ROSTER_OTEL_DIAGNOSTIC_HEADERS=1`.');
        return lines.join('\n');
    }
    for (const summary of summaries.sort((a, b) => b.rootDurationMs - a.rootDurationMs)) {
        lines.push(`## ${summary.rootName} — ${summary.rootDurationMs.toFixed(1)}ms`);
        lines.push(`trace: \`${summary.traceId}\`, spans: ${summary.spanCount}${summary.steps.length ? `, steps: ${summary.steps.map((step) => `\`${step}\``).join(', ')}` : ''}`);
        if (summary.errors.length) {
            const real = summary.errors.filter((error) => error.classification === 'error').length;
            const responseExits = summary.errors.filter((error) => error.classification === 'ihp_response_exit').length;
            lines.push(`errors: ${summary.errors.length} (${real} real-looking, ${responseExits} IHP response exits)`);
        }
        lines.push('', 'Slow spans:');
        for (const span of summary.topSpans.slice(0, 8)) lines.push(`- ${span.name}: ${span.durationMs.toFixed(1)}ms`);
        lines.push('', 'Largest exclusive-time gaps:');
        for (const span of summary.exclusiveTop.slice(0, 6)) lines.push(`- ${span.name}: ${span.exclusiveMs.toFixed(1)}ms exclusive / ${span.durationMs.toFixed(1)}ms total`);
        if (summary.duplicates.length) {
            lines.push('', 'Repeated spans:');
            for (const duplicate of summary.duplicates.slice(0, 6)) lines.push(`- ${duplicate.name}: count=${duplicate.count}, total=${duplicate.totalMs.toFixed(1)}ms, max=${duplicate.maxMs.toFixed(1)}ms`);
        }
        lines.push('');
    }
    return lines.join('\n');
}

export async function summarizeTempo(options) {
    const searchUrl = new URL('/api/search', options.tempoUrl);
    searchUrl.searchParams.set('tags', options.runId ? `bepis.trace.run=${options.runId}` : `service.name=${options.service}`);
    searchUrl.searchParams.set('limit', String(options.limit));
    const search = await fetchJson(searchUrl.toString());
    const traceRefs = search.traces || [];
    const traces = [];
    for (const ref of traceRefs) {
        const traceId = ref.traceID || ref.traceId;
        if (!traceId) continue;
        const trace = await fetchJson(new URL(`/api/traces/${traceId}`, options.tempoUrl).toString());
        const spans = flattenTrace(traceId, trace);
        if (options.runId && !spans.some((span) => span.attributes['bepis.trace.run'] === options.runId)) continue;
        const rootName = ref.rootTraceName || spans[0]?.name || traceId;
        if (rootName === '/favicon.ico') continue;
        traces.push({ traceId, rootName, spans });
    }
    const summaries = traces.map((trace) => summarizeTrace(trace.traceId, trace.rootName, trace.spans));
    return { options, traces, summaries };
}

if (import.meta.url === `file://${process.argv[1]}`) {
    const options = parseArgs(process.argv.slice(2));
    const result = await summarizeTempo(options);
    const markdown = renderMarkdown(options, result.summaries);
    if (options.outputDir) {
        fs.mkdirSync(options.outputDir, { recursive: true });
        fs.writeFileSync(path.join(options.outputDir, 'traces.json'), JSON.stringify(result.traces, null, 2));
        fs.writeFileSync(path.join(options.outputDir, 'summary.json'), JSON.stringify(result.summaries, null, 2));
        fs.writeFileSync(path.join(options.outputDir, 'summary.md'), markdown);
    }
    console.log(markdown);
}
