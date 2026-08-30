import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';

export const OTEL_ARTIFACT_SCHEMA = 'bepis.otel.profile.v2';
export const DEFAULT_LIMITS = Object.freeze({ maxBytes: 64 * 1024 * 1024, maxSpans: 100_000, maxAttributesPerSpan: 128, maxTraceViews: 500, maxSpansPerTrace: 1_000, maxGroups: 2_000 });

const round = (value) => Math.round(value * 10) / 10;
const percentile = (values, fraction) => values.length ? values[Math.min(values.length - 1, Math.ceil(values.length * fraction) - 1)] : 0;

export function resolveAllowedArtifact(inputPath, { root = process.cwd(), allowedRoots = ['output', '.pi/tmp'] } = {}) {
    const resolved = path.resolve(root, inputPath);
    const allowed = allowedRoots.map((entry) => path.resolve(root, entry));
    if (!allowed.some((entry) => resolved === entry || resolved.startsWith(`${entry}${path.sep}`))) {
        throw new Error(`Unsafe artifact path: expected a path below ${allowedRoots.join(' or ')}`);
    }
    if (fs.existsSync(resolved)) {
        const canonical = fs.realpathSync(resolved);
        const canonicalRoots = allowed.filter(fs.existsSync).map((entry) => fs.realpathSync(entry));
        if (!canonicalRoots.some((entry) => canonical === entry || canonical.startsWith(`${entry}${path.sep}`))) {
            throw new Error('Unsafe artifact symlink: target is outside allowed roots');
        }
        return canonical;
    }
    return resolved;
}

export function readBoundedJsonArtifact(inputPath, options = {}) {
    const limits = { ...DEFAULT_LIMITS, ...options };
    const stat = fs.statSync(inputPath);
    if (!stat.isFile()) throw new Error('Artifact is not a regular file');
    if (stat.size > limits.maxBytes) throw new Error(`Artifact exceeds ${limits.maxBytes} byte limit (${stat.size} bytes)`);
    try { return JSON.parse(fs.readFileSync(inputPath, 'utf8')); }
    catch (error) { throw new Error(`Malformed artifact JSON: ${error.message}`); }
}

export function readOtelArtifact(inputPath, options = {}) {
    const limits = { ...DEFAULT_LIMITS, ...options };
    const stat = fs.statSync(inputPath);
    if (!stat.isFile()) throw new Error('OpenTelemetry artifact is not a regular file');
    if (stat.size > limits.maxBytes) throw new Error(`OpenTelemetry artifact exceeds ${limits.maxBytes} byte limit (${stat.size} bytes)`);
    let documents;
    const content = fs.readFileSync(inputPath, 'utf8').trim();
    if (!content) documents = [];
    else {
        try {
            const parsed = JSON.parse(content);
            documents = Array.isArray(parsed) ? parsed : [parsed];
        } catch (wholeError) {
            try { documents = content.split('\n').filter(Boolean).map((line) => JSON.parse(line)); }
            catch (lineError) { throw new Error(`Malformed OpenTelemetry JSON: ${lineError.message}`); }
        }
    }
    return { documents, bytes: stat.size, limits };
}

export function otelValue(value = {}) {
    if ('stringValue' in value) return value.stringValue;
    if ('intValue' in value) return Number(value.intValue);
    if ('doubleValue' in value) return Number(value.doubleValue);
    if ('boolValue' in value) return Boolean(value.boolValue);
    if ('arrayValue' in value) return (value.arrayValue.values || []).map(otelValue);
    return null;
}

export function attrsToObject(attributes = []) {
    if (!Array.isArray(attributes)) return attributes && typeof attributes === 'object' ? attributes : {};
    return Object.fromEntries(attributes.map((attribute) => [attribute.key, otelValue(attribute.value || {})]));
}

function nano(value) { try { return BigInt(value || 0); } catch { return 0n; } }
function durationMs(span) {
    if (Number.isFinite(span.durationMs)) return round(span.durationMs);
    const start = nano(span.startTimeUnixNano || span.start_time_unix_nano);
    const end = nano(span.endTimeUnixNano || span.end_time_unix_nano);
    return end > start ? round(Number(end - start) / 1_000_000) : 0;
}

function pushSpan(output, span, inherited, limits) {
    if (output.length >= limits.maxSpans) throw new Error(`OpenTelemetry artifact exceeds ${limits.maxSpans} span limit`);
    if (Array.isArray(span.attributes) && span.attributes.length > limits.maxAttributesPerSpan) throw new Error(`Span exceeds ${limits.maxAttributesPerSpan} attribute limit`);
    const attributes = attrsToObject(span.attributes || {});
    const resource = inherited.resource || attrsToObject(span.resource?.attributes || span.resource || {});
    const statusCode = String(span.status?.code || span.statusCode || 'STATUS_CODE_UNSET');
    output.push({
        traceId: span.traceId || span.trace_id || inherited.traceId || '',
        spanId: span.spanId || span.span_id || span.id || '',
        parentSpanId: span.parentSpanId || span.parent_span_id || span.parentId || '',
        name: String(span.name || span.spanName || 'span').slice(0, 200),
        startNs: String(span.startTimeUnixNano || span.start_time_unix_nano || '0'),
        endNs: String(span.endTimeUnixNano || span.end_time_unix_nano || '0'),
        durationMs: durationMs(span),
        statusCode,
        statusMessage: String(span.status?.message || span.statusMessage || '').slice(0, 500),
        attributes,
        resource,
        events: (span.events || []).slice(0, 100).map((event) => ({ name: String(event.name || '').slice(0, 100), attributes: attrsToObject(event.attributes || {}) })),
        scopeName: inherited.scopeName || span.scopeName || '',
    });
}

function walk(value, output, inherited, limits) {
    if (Array.isArray(value)) { for (const item of value) walk(item, output, inherited, limits); return; }
    if (!value || typeof value !== 'object') return;
    const resource = value.resource?.attributes ? { ...inherited.resource, ...attrsToObject(value.resource.attributes) } : inherited.resource;
    const scopeName = value.scope?.name || value.instrumentationLibrary?.name || inherited.scopeName;
    const next = { ...inherited, resource, scopeName };
    if (value.traceId || value.trace_id || value.spanId || value.span_id) pushSpan(output, value, next, limits);
    for (const key of ['resourceSpans', 'scopeSpans', 'instrumentationLibrarySpans', 'batches', 'spans']) {
        if (value[key]) walk(value[key], output, next, limits);
    }
}

export function normalizeOtelDocuments(documents, options = {}) {
    const limits = { ...DEFAULT_LIMITS, ...options };
    const spans = [];
    walk(documents, spans, { resource: {}, scopeName: '' }, limits);
    return spans;
}

function normalizedPath(value) {
    const pathOnly = String(value || '').split(/[?#]/, 1)[0]
        .replace(/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/gi, ':uuid')
        .replace(/\/[0-9]{3,}(?=\/|$)/g, '/:id');
    if (!pathOnly) return '';
    const digest = createHash('sha256').update(pathOnly).digest('hex').slice(0, 16);
    return `path:${digest}`;
}

function safeClosedIdentity(value, prefix) {
    const identity = String(value || '');
    if (!identity) return '';
    if (/^[A-Z][A-Za-z0-9]{0,149}Action$/.test(identity)) return identity;
    const digest = createHash('sha256').update(identity).digest('hex').slice(0, 16);
    return `${prefix}:${digest}`;
}

export function routeIdentity(span) {
    const attributes = span.attributes || {};
    const canonicalRoute = attributes['http.route'] || '';
    const route = canonicalRoute ? safeClosedIdentity(canonicalRoute, 'route') : normalizedPath(attributes['url.path'] || attributes['http.target'] || '');
    const action = safeClosedIdentity(attributes['bepis.ihp.action'] || attributes['bepis.action'] || '', 'action');
    const method = attributes['http.request.method'] || attributes['http.method'] || '';
    return { route: String(route).slice(0, 300), action: String(action).slice(0, 200), method: String(method).slice(0, 20) };
}

export function classifyStatus(span) {
    const error = span.statusCode === 'STATUS_CODE_ERROR' || span.statusCode === '2';
    if (!error) return 'ok';
    if (/ResponseException/i.test(span.statusMessage) || span.attributes?.['bepis.ihp.response_exit'] === true) return 'ihp_response_exit';
    return 'error';
}

export function classifyCategory(span) {
    const name = span.name.toLowerCase();
    const attrs = span.attributes || {};
    if (name.includes('provider') || attrs['bepis.provider.kind'] || attrs['bepis.provider.operation']) return 'provider';
    if (name.includes('postgres') || name.includes('sql') || name.startsWith('db.') || attrs['db.system']) return 'database';
    if (name.includes('live_update') || name.includes('websocket')) return 'live-update';
    if (name.includes('render') || name.includes('html')) return 'render';
    if (name.includes('runtime') || name.includes('gc') || name.includes('heap')) return 'runtime';
    if (name.includes('response') || Number.isFinite(Number(attrs['http.response.body.size'])) || Number.isFinite(Number(attrs['html.bytes']))) return 'response';
    if (name.includes('job')) return 'job';
    if (name.includes('export')) return 'export';
    return 'application';
}

function unionDuration(intervals, parentStart, parentEnd) {
    const clipped = intervals.map(([start, end]) => [start < parentStart ? parentStart : start, end > parentEnd ? parentEnd : end])
        .filter(([start, end]) => end > start).sort((a, b) => a[0] < b[0] ? -1 : 1);
    let total = 0n; let current = null;
    for (const interval of clipped) {
        if (!current || interval[0] > current[1]) { if (current) total += current[1] - current[0]; current = [...interval]; }
        else if (interval[1] > current[1]) current[1] = interval[1];
    }
    if (current) total += current[1] - current[0];
    return Number(total) / 1_000_000;
}

function addExclusiveTime(spans) {
    const children = new Map();
    for (const span of spans) {
        const parentKey = `${span.traceId}\u0000${span.parentSpanId}`;
        if (!children.has(parentKey)) children.set(parentKey, []);
        children.get(parentKey).push(span);
    }
    return spans.map((span) => {
        const start = nano(span.startNs); const end = nano(span.endNs);
        const childIntervals = (children.get(`${span.traceId}\u0000${span.spanId}`) || []).map((child) => [nano(child.startNs), nano(child.endNs)]);
        return { ...span, exclusiveMs: round(Math.max(0, span.durationMs - unionDuration(childIntervals, start, end))) };
    });
}

function aggregate(rows, keyFn, limits) {
    const groups = new Map();
    for (const row of rows) {
        const key = keyFn(row);
        if (!groups.has(key)) groups.set(key, []);
        groups.get(key).push(row);
    }
    if (groups.size > limits.maxGroups) throw new Error(`OpenTelemetry artifact exceeds ${limits.maxGroups} aggregate-group limit`);
    return groups;
}

function stats(values) {
    const sorted = values.map(Number).filter(Number.isFinite).sort((a, b) => a - b);
    return { sampleCount: sorted.length, median: round(percentile(sorted, 0.5)), p95: round(percentile(sorted, 0.95)), max: round(sorted.at(-1) || 0), total: round(sorted.reduce((sum, value) => sum + value, 0)) };
}

export function traceReference(traceId) {
    return createHash('sha256').update(String(traceId || '')).digest('hex').slice(0, 32);
}

function safeSpan(span) {
    const identity = routeIdentity(span);
    return { traceId: traceReference(span.traceId), spanId: span.spanId, parentSpanId: span.parentSpanId, name: span.name, ...identity, durationMs: span.durationMs, exclusiveMs: span.exclusiveMs, category: classifyCategory(span), status: classifyStatus(span) };
}

function safeContext(metadata) {
    if (!metadata) return null;
    const base = metadata.metadata || metadata;
    const journey = metadata.journey || (Array.isArray(metadata.steps) ? metadata : null);
    return {
        scenario: base.scenario || journey?.scenario || null,
        role: base.role || journey?.role || null,
        runId: base.runId || journey?.runId || null,
        rate: base.rate || null,
        duration: base.duration || null,
        vus: base.vus || null,
        maxVus: base.maxVus || null,
        telemetry: base.telemetry || null,
        journey: journey ? { startedAt: journey.startedAt || null, completedAt: journey.completedAt || null, steps: (journey.steps || []).slice(0, 500).map((step) => ({ name: String(step.name || '').slice(0, 100), ok: Boolean(step.ok), status: step.status || null, durationMs: Number(step.durationMs || 0) })) } : null,
    };
}

export function summarizeOtelSpans(inputSpans, { metadata = null, source = {}, limits: customLimits = {} } = {}) {
    const limits = { ...DEFAULT_LIMITS, ...customLimits };
    if (inputSpans.length > limits.maxSpans) throw new Error(`OpenTelemetry materialization exceeds ${limits.maxSpans} span limit (${inputSpans.length} spans)`);
    const spans = addExclusiveTime(inputSpans);
    const byTrace = aggregate(spans, (span) => span.traceId || 'missing-trace-id', limits);
    const spanGroups = [...aggregate(spans, (span) => {
        const identity = routeIdentity(span); return `${identity.method}\u0000${identity.route}\u0000${identity.action}\u0000${span.name}`;
    }, limits).values()].map((rows) => {
        const identity = routeIdentity(rows[0]);
        const statuses = { ok: 0, ihpResponseExit: 0, error: 0 };
        for (const row of rows) { const status = classifyStatus(row); if (status === 'ihp_response_exit') statuses.ihpResponseExit++; else statuses[status]++; }
        return { ...identity, span: rows[0].name, category: classifyCategory(rows[0]), durationMs: stats(rows.map((row) => row.durationMs)), exclusiveMs: stats(rows.map((row) => row.exclusiveMs)), statuses };
    }).sort((a, b) => b.durationMs.p95 - a.durationMs.p95);
    const routeGroups = [...aggregate(spans.filter((span) => { const id = routeIdentity(span); return id.route || id.action; }), (span) => {
        const id = routeIdentity(span); return `${id.method}\u0000${id.route}\u0000${id.action}`;
    }, limits).values()].map((rows) => ({ ...routeIdentity(rows[0]), durationMs: stats(rows.map((row) => row.durationMs)), spanCount: rows.length })).sort((a, b) => b.durationMs.p95 - a.durationMs.p95);
    const categoryGroups = [...aggregate(spans, classifyCategory, limits).entries()].map(([category, rows]) => ({ category, durationMs: stats(rows.map((row) => row.durationMs)), exclusiveMs: stats(rows.map((row) => row.exclusiveMs)) })).sort((a, b) => b.durationMs.total - a.durationMs.total);
    const statuses = { ok: 0, ihpResponseExit: 0, error: 0 };
    for (const span of spans) { const status = classifyStatus(span); if (status === 'ihp_response_exit') statuses.ihpResponseExit++; else statuses[status]++; }
    const traceViews = [...byTrace.entries()].slice(0, limits.maxTraceViews).map(([traceId, rows]) => {
        if (rows.length > limits.maxSpansPerTrace) {
            const traceRef = createHash('sha256').update(String(traceId)).digest('hex').slice(0, 16);
            throw new Error(`Trace ref ${traceRef} exceeds ${limits.maxSpansPerTrace} span view limit`);
        }
        const safe = rows.map(safeSpan);
        const root = safe.find((span) => !span.parentSpanId || !safe.some((candidate) => candidate.spanId === span.parentSpanId)) || safe[0];
        return { traceId: traceReference(traceId), rootName: root?.name || '', rootDurationMs: root?.durationMs || 0, spanCount: safe.length, spans: safe };
    });
    const repeatedSpanGroups = spanGroups.filter((group) => group.durationMs.sampleCount > 1).slice(0, 200);
    const slowestSpans = spans.map(safeSpan).sort((a, b) => b.durationMs - a.durationMs).slice(0, 100);
    const componentSamples = spans.filter((span) => Number.isFinite(Number(span.attributes['html.bytes']))).map((span) => ({ ...safeSpan(span), bytes: Number(span.attributes['html.bytes']) })).sort((a, b) => b.bytes - a.bytes);
    const largestComponents = componentSamples.slice(0, 100);
    const renderCounterSamples = spans.flatMap((span) => Object.entries(span.attributes).filter(([key]) => key.startsWith('render.')).map(([counter, value]) => ({ ...safeSpan(span), counter, value: Number(value) }))).filter((row) => Number.isFinite(row.value)).sort((a, b) => b.value - a.value);
    const renderCounters = renderCounterSamples.slice(0, 200);
    const responseSizeSamples = spans.flatMap((span) => ['http.response.body.size', 'html.bytes'].flatMap((attribute) => {
        const bytes = Number(span.attributes[attribute]);
        return Number.isFinite(bytes) ? [{ ...safeSpan(span), attribute, bytes }] : [];
    })).sort((a, b) => b.bytes - a.bytes);
    const responseSizes = responseSizeSamples.slice(0, 200);
    const loadPressure = metadata?.loadPressure || metadata?.summary?.loadPressure || metadata?.summary?.k6 || (metadata?.summary && ('droppedIterations' in metadata.summary || 'vuSaturation' in metadata.summary) ? {
        iterations: metadata.summary.iterations || metadata.summary.completedIterations || metadata.summary.iterationCount || 0,
        droppedIterations: metadata.summary.droppedIterations || 0,
        vuSaturation: metadata.summary.vuSaturation || 0,
        vus: metadata.metadata?.vus || metadata.summary.vus || 0,
    } : null);
    return {
        schemaVersion: OTEL_ARTIFACT_SCHEMA,
        source,
        context: safeContext(metadata),
        summary: { traceCount: byTrace.size, traceViewCount: traceViews.length, omittedTraceViews: Math.max(0, byTrace.size - traceViews.length), spanCount: spans.length, routeGroupCount: routeGroups.length, spanGroupCount: spanGroups.length, repeatedSpanGroupCount: repeatedSpanGroups.length, renderCounterSampleCount: renderCounterSamples.length, componentByteSampleCount: componentSamples.length, responseSizeSampleCount: responseSizeSamples.length, statuses },
        loadPressure,
        routes: routeGroups,
        spanGroups,
        repeatedSpanGroups,
        categories: categoryGroups,
        slowestSpans,
        largestComponents,
        renderCounters,
        responseSizes,
        traceViews,
    };
}

export function buildOtelSummary(inputPath, options = {}) {
    const artifact = readOtelArtifact(inputPath, options.limits);
    const spans = normalizeOtelDocuments(artifact.documents, artifact.limits);
    return summarizeOtelSpans(spans, { metadata: options.metadata || null, source: { format: options.format || 'collector-file-export', bytes: artifact.bytes }, limits: artifact.limits });
}
