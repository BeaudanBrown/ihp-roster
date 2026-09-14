#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { normalizeOtelDocuments, summarizeOtelSpans } from './otel-artifact.mjs';
import { renderOtelSummaryMarkdown } from './otel-profile-summary.mjs';

const DEFAULT_TEMPO_URL = process.env.TEMPO_URL || 'http://127.0.0.1:3200';
const DEFAULT_SERVICE = process.env.OTEL_SERVICE_NAME || 'ihp-roster-dev';

function usage() { console.log(`Usage: node e2e/otel-trace-summary.mjs [options]\n\n  --tempo-url <url>\n  --service <name>\n  --run-id <id>\n  --limit <n>          Tempo search limit (1..500, default 200)\n  --timeout-ms <n>     Per-request timeout (100..30000, default 10000)\n  --output-dir <path>\n`); }
function parseArgs(argv) {
    const options = { tempoUrl: DEFAULT_TEMPO_URL, service: DEFAULT_SERVICE, runId: process.env.OTEL_TRACE_RUN_ID || null, limit: 200, timeoutMs: 10_000, outputDir: null };
    const args = [...argv]; if (args.includes('--help')) { usage(); process.exit(0); }
    while (args.length) {
        const arg = args.shift(); const [flag, inline] = arg.includes('=') ? arg.split(/=(.*)/s, 2) : [arg, null]; const next = () => inline ?? args.shift();
        if (flag === '--tempo-url') options.tempoUrl = next(); else if (flag === '--service') options.service = next(); else if (flag === '--run-id') options.runId = next(); else if (flag === '--limit') options.limit = Number(next()); else if (flag === '--timeout-ms') options.timeoutMs = Number(next()); else if (flag === '--output-dir') options.outputDir = next(); else throw new Error(`Unknown argument: ${arg}`);
    }
    if (!options.tempoUrl || !options.service) throw new Error('--tempo-url and --service are required');
    if (!Number.isInteger(options.limit) || options.limit < 1 || options.limit > 500) throw new Error('--limit must be an integer from 1 to 500');
    if (!Number.isInteger(options.timeoutMs) || options.timeoutMs < 100 || options.timeoutMs > 30_000) throw new Error('--timeout-ms must be an integer from 100 to 30000');
    return options;
}
async function fetchJson(url, timeoutMs, budget) {
    const response = await fetch(url, { signal: AbortSignal.timeout(timeoutMs) });
    if (!response.ok) throw new Error(`${response.status} ${response.statusText} from ${new URL(url).origin}`);
    const contentLength = Number(response.headers.get('content-length') || 0);
    if (contentLength > 64 * 1024 * 1024) throw new Error(`Tempo response exceeds 67108864 byte limit (${contentLength} bytes)`);
    const text = await response.text();
    const bytes = Buffer.byteLength(text);
    if (bytes > 64 * 1024 * 1024) throw new Error('Tempo response exceeds 67108864 byte limit');
    budget.bytes += bytes;
    if (budget.bytes > 64 * 1024 * 1024) throw new Error(`Tempo query materialization exceeds 67108864 byte limit (${budget.bytes} bytes)`);
    try { return JSON.parse(text); } catch (error) { throw new Error(`Malformed Tempo JSON: ${error.message}`); }
}

export async function summarizeTempo(options) {
    const searchUrl = new URL('/api/search', options.tempoUrl);
    searchUrl.searchParams.set('tags', options.runId ? `bepis.trace.run=${options.runId}` : `service.name=${options.service}`);
    searchUrl.searchParams.set('limit', String(options.limit));
    const budget = { bytes: 0 };
    const search = await fetchJson(searchUrl, options.timeoutMs, budget);
    const references = (search.traces || []).slice(0, options.limit);
    const spans = [];
    const maxSpans = options.maxSpans || 100_000;
    let materializedSpanCount = 0;
    for (const reference of references) {
        const traceId = reference.traceID || reference.traceId; if (!traceId) continue;
        const document = await fetchJson(new URL(`/api/traces/${encodeURIComponent(traceId)}`, options.tempoUrl), options.timeoutMs, budget);
        const remaining = maxSpans - materializedSpanCount;
        if (remaining <= 0) throw new Error(`Tempo query materialization exceeds ${maxSpans} span limit`);
        let normalized;
        try { normalized = normalizeOtelDocuments(document, { maxSpans: remaining }); }
        catch (error) {
            if (/span limit/.test(error.message)) throw new Error(`Tempo query materialization exceeds ${maxSpans} span limit`);
            throw error;
        }
        materializedSpanCount += normalized.length;
        for (const span of normalized) {
            const identified = span.traceId ? span : { ...span, traceId };
            if (!options.runId || identified.attributes['bepis.trace.run'] === options.runId) spans.push(identified);
        }
    }
    return summarizeOtelSpans(spans, { metadata: { scenario: options.metadata?.scenario || 'browser', service: options.service, runId: options.runId, journey: options.metadata || null }, source: { format: 'tempo-query-materialization', traceReferenceCount: references.length } });
}

if (import.meta.url === `file://${process.argv[1]}`) {
    try {
        const options = parseArgs(process.argv.slice(2));
        const journeyPath = options.outputDir ? path.join(options.outputDir, 'journey.json') : null;
        options.metadata = journeyPath && fs.existsSync(journeyPath) ? JSON.parse(fs.readFileSync(journeyPath, 'utf8')) : null;
        const report = await summarizeTempo(options);
        const markdown = renderOtelSummaryMarkdown(report, `${options.tempoUrl}/api/search`);
        if (options.outputDir) {
            fs.mkdirSync(options.outputDir, { recursive: true });
            fs.writeFileSync(path.join(options.outputDir, 'otel-summary.json'), `${JSON.stringify(report, null, 2)}\n`);
            fs.writeFileSync(path.join(options.outputDir, 'otel-summary.md'), markdown);
            // Compatibility aliases during the schema-v2 transition.
            fs.writeFileSync(path.join(options.outputDir, 'summary.json'), `${JSON.stringify(report, null, 2)}\n`);
            fs.writeFileSync(path.join(options.outputDir, 'summary.md'), markdown);
        }
        console.log(markdown);
    } catch (error) { console.error(`OpenTelemetry summary failed: ${error.message}`); process.exit(1); }
}
