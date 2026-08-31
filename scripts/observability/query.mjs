#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { createHash, randomBytes } from 'node:crypto';
import { normalizeOtelDocuments, summarizeOtelSpans, traceReference } from '../../e2e/otel-artifact.mjs';
import { compareOtelProfiles } from '../../e2e/profile-compare.mjs';

export const LIMITS = Object.freeze({
    maxWindowMinutes: 15,
    maxLookbackDays: 7,
    maxTraces: 20,
    maxSpans: 2_000,
    maxSpansPerTrace: 500,
    maxResponseBytes: 2 * 1024 * 1024,
    maxTotalBytes: 8 * 1024 * 1024,
    maxLogRows: 200,
    timeoutMs: 3_000,
    totalTimeoutMs: 20_000,
    artifactLifetimeHours: 24,
});
const ARTIFACT_ROOT = '.pi/tmp/observability-query';
const PRODUCTION_SERVICE_NAME = 'ihp-roster';
const REDACTED_LOG_BODY = '[redacted production journal event]';
const SAFE_ATTRIBUTE_KEYS = new Set([
    'http.route', 'http.request.method', 'http.method', 'http.response.status_code', 'http.status_code',
    'bepis.ihp.action', 'bepis.action', 'bepis.action.kind', 'bepis.outcome', 'bepis.app_error.code',
    'bepis.app_error.severity', 'bepis.app_error.recovery', 'bepis.provider', 'bepis.provider.kind',
    'bepis.provider.operation', 'bepis.provider.method', 'bepis.provider.status_class', 'bepis.job.kind',
    'bepis.job.attempt', 'bepis.job.max_attempts', 'bepis.job.retry_state', 'bepis.live_update.command',
    'bepis.export.kind', 'db.system', 'html.bytes', 'http.response.body.size', 'render.components',
    'render.fragments', 'render.rows', 'render.bytes',
]);
const SAFE_RESOURCE_KEYS = new Set([
    'service.name', 'service.namespace', 'service.version', 'deployment.environment.name',
    'bepis.deployment.slot', 'service.instance.id', 'host.name',
]);

function digest(value, length = 16) { return createHash('sha256').update(String(value)).digest('hex').slice(0, length); }
function boundedInteger(value, name, minimum, maximum) {
    const parsed = Number(value);
    if (!Number.isInteger(parsed) || parsed < minimum || parsed > maximum) throw new Error(`${name} must be an integer from ${minimum} to ${maximum}`);
    return parsed;
}
function parseInstant(value, name) {
    const timestamp = Date.parse(value);
    if (!Number.isFinite(timestamp)) throw new Error(`${name} must be an ISO-8601 timestamp`);
    return timestamp;
}
function tailnetHostname(hostname) {
    if (/^[a-z0-9-]+(?:\.[a-z0-9-]+)*\.ts\.net$/i.test(hostname)) return true;
    const octets = hostname.split('.').map(Number);
    if (octets.length === 4 && octets.every((part) => Number.isInteger(part) && part >= 0 && part <= 255)) {
        const value = (((octets[0] * 256 + octets[1]) * 256 + octets[2]) * 256 + octets[3]) >>> 0;
        return value >= 0x64400000 && value <= 0x647fffff;
    }
    return hostname.toLowerCase().startsWith('[fd7a:115c:a1e0:') || hostname.toLowerCase().startsWith('fd7a:115c:a1e0:');
}
export function validateQueryEndpoint(value, kind, { allowLoopback = false, expectedPort = kind === 'tempo' ? '3200' : '3101' } = {}) {
    if (!value) throw new Error(`Missing configured ${kind} query endpoint`);
    let url;
    try { url = new URL(value); } catch { throw new Error(`Invalid configured ${kind} query endpoint`); }
    const loopback = ['127.0.0.1', '::1', '[::1]'].includes(url.hostname);
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash || (url.pathname !== '/' && url.pathname !== '')) {
        throw new Error(`Configured ${kind} endpoint must be an HTTP(S) origin without credentials, path, query, or fragment`);
    }
    if (url.port !== String(expectedPort)) throw new Error(`Configured ${kind} endpoint must use query port ${expectedPort}`);
    if (allowLoopback ? !loopback : !tailnetHostname(url.hostname)) throw new Error(`Configured ${kind} endpoint is not an approved ${allowLoopback ? 'loopback' : 'tailnet'} query address`);
    return new URL(`${url.protocol}//${url.host}`);
}
export function resolveQueryTarget(value = 'development', environment = process.env) {
    const target = ({ dev: 'development', local: 'development', prod: 'production' })[value] || value;
    if (!['development', 'production'].includes(target)) throw new Error('--target must be development or production');
    if (target === 'development') {
        const tempoPort = String(environment.IHP_ROSTER_DEV_TEMPO_PORT || '3200');
        const lokiPort = String(environment.IHP_ROSTER_DEV_LOKI_PORT || '3101');
        const tempoValue = environment.BEPIS_DEVELOPMENT_TEMPO_QUERY_URL || `http://127.0.0.1:${tempoPort}`;
        const lokiValue = environment.BEPIS_DEVELOPMENT_LOKI_QUERY_URL || null;
        return {
            target,
            serviceName: environment.BEPIS_WORKSPACE_OTEL_SERVICE_NAME || environment.OTEL_SERVICE_NAME || 'ihp-roster-dev',
            tempoUrl: validateQueryEndpoint(tempoValue, 'tempo', { allowLoopback: true, expectedPort: tempoPort }),
            lokiUrl: lokiValue ? validateQueryEndpoint(lokiValue, 'loki', { allowLoopback: true, expectedPort: lokiPort }) : null,
        };
    }
    return {
        target,
        serviceName: PRODUCTION_SERVICE_NAME,
        tempoUrl: validateQueryEndpoint(environment.BEPIS_PRODUCTION_TEMPO_QUERY_URL, 'tempo'),
        lokiUrl: environment.BEPIS_PRODUCTION_LOKI_QUERY_URL ? validateQueryEndpoint(environment.BEPIS_PRODUCTION_LOKI_QUERY_URL, 'loki') : null,
    };
}

function safeScalar(value) {
    if (typeof value === 'number' || typeof value === 'boolean') return value;
    const text = String(value ?? '');
    return /^[A-Za-z0-9_.:-]{0,64}$/.test(text) ? text : `value:${digest(text)}`;
}
function safeSpanName(name) {
    const text = String(name || 'span');
    if (/^[A-Z][A-Za-z0-9]{0,149}Action$/.test(text)) return text;
    if (/^(?:bepis|provider|render|response|runtime|db|postgresql|http|application|live_update|websocket|html|job|export)[. _a-z0-9-]{0,140}$/i.test(text)) return text;
    return `span:${digest(text)}`;
}
function sanitizeSpan(span) {
    return {
        ...span,
        spanId: /^[0-9a-f]{8,32}$/i.test(String(span.spanId || '')) ? String(span.spanId).toLowerCase() : `span-${digest(span.spanId)}`,
        parentSpanId: !span.parentSpanId ? '' : (/^[0-9a-f]{8,32}$/i.test(String(span.parentSpanId)) ? String(span.parentSpanId).toLowerCase() : `span-${digest(span.parentSpanId)}`),
        name: safeSpanName(span.name),
        statusMessage: /ResponseException/i.test(String(span.statusMessage || '')) ? 'ResponseException' : '',
        attributes: Object.fromEntries(Object.entries(span.attributes || {}).filter(([key]) => SAFE_ATTRIBUTE_KEYS.has(key)).map(([key, value]) => [key, safeScalar(value)])),
        resource: Object.fromEntries(Object.entries(span.resource || {}).filter(([key]) => SAFE_RESOURCE_KEYS.has(key)).map(([key, value]) => [key, safeScalar(value)])),
        events: [],
    };
}
function backendError(kind, error) {
    if (error?.name === 'TimeoutError' || error?.name === 'AbortError') return new Error(`${kind} query timed out after ${LIMITS.timeoutMs}ms`);
    if (/authorization failed|backend unavailable|response exceeded|malformed JSON/.test(error?.message || '')) return error;
    return new Error(`${kind} backend unavailable`);
}
async function boundedJson(url, kind, budget, fetchImpl = fetch) {
    const remainingMs = (budget.deadline || (Date.now() + LIMITS.totalTimeoutMs)) - Date.now();
    if (remainingMs <= 0) throw new Error(`${kind} query exceeded ${LIMITS.totalTimeoutMs}ms total timeout`);
    let response;
    try { response = await fetchImpl(url, { method: 'GET', redirect: 'error', signal: AbortSignal.timeout(Math.min(LIMITS.timeoutMs, remainingMs)), headers: { accept: 'application/json' } }); }
    catch (error) { throw backendError(kind, error); }
    if (response.status === 401 || response.status === 403) throw new Error(`${kind} authorization failed`);
    if (!response.ok) throw new Error(`${kind} backend unavailable (${response.status})`);
    const declared = Number(response.headers.get('content-length') || 0);
    if (declared > LIMITS.maxResponseBytes) throw new Error(`${kind} response exceeded ${LIMITS.maxResponseBytes} byte limit`);
    const reader = response.body?.getReader();
    const chunks = []; let bytes = 0;
    if (reader) {
        while (true) {
            const { done, value } = await reader.read(); if (done) break;
            bytes += value.byteLength;
            if (bytes > LIMITS.maxResponseBytes || budget.bytes + bytes > LIMITS.maxTotalBytes) { await reader.cancel(); throw new Error(`${kind} response exceeded bounded byte limit`); }
            chunks.push(Buffer.from(value));
        }
    } else {
        const value = Buffer.from(await response.arrayBuffer()); bytes = value.length; chunks.push(value);
    }
    budget.bytes += bytes;
    try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
    catch { throw new Error(`${kind} returned malformed JSON`); }
}

function queryWindow({ minutes = 5, end = Date.now() } = {}) {
    const duration = boundedInteger(minutes, '--minutes', 1, LIMITS.maxWindowMinutes) * 60_000;
    const endMs = typeof end === 'number' ? end : parseInstant(end, '--end');
    const now = Date.now();
    if (endMs > now + 60_000 || endMs < now - LIMITS.maxLookbackDays * 86_400_000) throw new Error(`query end must be within the last ${LIMITS.maxLookbackDays} days`);
    return { startMs: endMs - duration, endMs, minutes: duration / 60_000 };
}
function traceWindows(spans) {
    const groups = new Map();
    for (const span of spans) {
        if (!span.traceId) continue;
        const start = BigInt(span.startNs || 0); const end = BigInt(span.endNs || 0);
        const current = groups.get(span.traceId);
        groups.set(span.traceId, current ? { startNs: start < current.startNs ? start : current.startNs, endNs: end > current.endNs ? end : current.endNs } : { startNs: start, endNs: end });
    }
    return [...groups.entries()].map(([raw, range]) => ({ traceId: traceReference(raw), startNs: String(range.startNs), endNs: String(range.endNs) }));
}
export async function queryRecent(options, dependencies = {}) {
    const tempo = validateQueryEndpoint(options.tempoUrl, 'tempo', { allowLoopback: dependencies.allowLoopback, expectedPort: dependencies.expectedPort });
    const window = queryWindow(options);
    const limit = boundedInteger(options.limit ?? 10, '--limit', 1, LIMITS.maxTraces);
    const budget = { bytes: 0, deadline: Date.now() + LIMITS.totalTimeoutMs }; const fetchImpl = dependencies.fetchImpl || fetch;
    const searchUrl = new URL('/api/search', tempo);
    const serviceName = options.serviceName || PRODUCTION_SERVICE_NAME;
    searchUrl.searchParams.set('tags', `service.name=${serviceName}`);
    searchUrl.searchParams.set('start', String(Math.floor(window.startMs / 1000)));
    searchUrl.searchParams.set('end', String(Math.floor(window.endMs / 1000)));
    searchUrl.searchParams.set('limit', String(limit));
    const search = await boundedJson(searchUrl, 'Tempo', budget, fetchImpl);
    const references = (search.traces || []).slice(0, limit);
    let spans = [];
    for (const reference of references) {
        const rawTraceId = reference.traceID || reference.traceId;
        if (!/^[0-9a-f]{16,64}$/i.test(String(rawTraceId || ''))) continue;
        const traceUrl = new URL(`/api/traces/${rawTraceId}`, tempo);
        const document = await boundedJson(traceUrl, 'Tempo', budget, fetchImpl);
        const normalized = normalizeOtelDocuments(document, { maxSpans: LIMITS.maxSpans });
        if (normalized.length > LIMITS.maxSpansPerTrace) throw new Error(`trace ref ${traceReference(rawTraceId).slice(0, 16)} exceeded ${LIMITS.maxSpansPerTrace} span limit`);
        spans.push(...normalized.map((span) => sanitizeSpan(span.traceId ? span : { ...span, traceId: rawTraceId })));
        if (spans.length > LIMITS.maxSpans) throw new Error(`query exceeded ${LIMITS.maxSpans} span limit`);
    }
    const report = summarizeOtelSpans(spans, {
        metadata: { scenario: `${options.target || 'production'}-recent`, service: serviceName },
        source: { format: 'tempo-query-materialization', target: options.target || 'production', endpointRef: digest(tempo.origin), queriedAt: new Date().toISOString(), windowStart: new Date(window.startMs).toISOString(), windowEnd: new Date(window.endMs).toISOString(), traceLimit: limit, responseBytes: budget.bytes },
        limits: { maxSpans: LIMITS.maxSpans, maxSpansPerTrace: LIMITS.maxSpansPerTrace, maxTraceViews: LIMITS.maxTraces },
    });
    report.traceWindows = traceWindows(spans);
    report.deployments = [...new Map(spans.map((span) => {
        const candidateVersion = String(span.resource?.['service.version'] || 'unknown');
        const candidateSlot = String(span.resource?.['bepis.deployment.slot'] || 'unknown');
        const version = /^(?:[0-9a-f]{7,64}(?:-dirty)?|v?\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?)$/i.test(candidateVersion) ? candidateVersion : `version:${digest(candidateVersion)}`;
        const slot = candidateSlot === 'production' ? candidateSlot : 'unknown';
        return [`${version}\u0000${slot}`, { version, slot }];
    })).values()].slice(0, 10);
    return report;
}

function safeLogMetadata(metadata = {}) {
    const unit = metadata.systemd_unit ?? metadata['systemd.unit'];
    const priority = metadata.systemd_priority ?? metadata['systemd.priority'];
    return {
        ...(unit === 'app.service' || unit === 'worker.service' ? { systemd_unit: unit } : {}),
        ...(/^[0-7]$/.test(String(priority ?? '')) ? { systemd_priority: String(priority) } : {}),
    };
}
export async function queryRelatedLogs(options, dependencies = {}) {
    const loki = validateQueryEndpoint(options.lokiUrl, 'loki', { allowLoopback: dependencies.allowLoopback, expectedPort: dependencies.expectedPort });
    if (!/^[0-9a-f]{32}$/.test(options.traceRef || '')) throw new Error('--trace-ref must be a 32-character safe trace reference');
    const report = readQuerySummary(options.artifactDir);
    const trace = (report.traceWindows || []).find((row) => row.traceId === options.traceRef);
    if (!trace) throw new Error('safe trace reference was not found in the bounded artifact');
    const padding = 30_000_000_000n;
    const start = BigInt(trace.startNs) > padding ? BigInt(trace.startNs) - padding : 0n;
    const end = BigInt(trace.endNs) + padding;
    const nowNs = BigInt(Date.now()) * 1_000_000n;
    const earliestNs = nowNs - BigInt(LIMITS.maxLookbackDays) * 86_400_000_000_000n;
    if (end - start > BigInt(LIMITS.maxWindowMinutes) * 60_000_000_000n) throw new Error('related-log window exceeds bounded query limit');
    if (start < earliestNs || end > nowNs + 60_000_000_000n) throw new Error(`related-log window must be within the last ${LIMITS.maxLookbackDays} days`);
    const url = new URL('/loki/api/v1/query_range', loki);
    url.searchParams.set('query', `{service_name="${options.serviceName || PRODUCTION_SERVICE_NAME}"}`);
    url.searchParams.set('start', String(start)); url.searchParams.set('end', String(end)); url.searchParams.set('limit', String(LIMITS.maxLogRows));
    const budget = { bytes: 0, deadline: Date.now() + LIMITS.totalTimeoutMs };
    const response = await boundedJson(url, 'Loki', budget, dependencies.fetchImpl || fetch);
    const streams = response.data?.result || [];
    let rowCount = 0;
    for (const stream of streams) {
        for (const value of stream.values || []) {
            rowCount += 1;
            if (value[1] !== REDACTED_LOG_BODY) throw new Error('Loki returned non-redacted log content; artifact was not written');
        }
    }
    if (rowCount > LIMITS.maxLogRows) throw new Error(`Loki returned more than ${LIMITS.maxLogRows} bounded log rows; artifact was not written`);
    const rows = streams.flatMap((stream) => (stream.values || []).map((value) => ({ timestampNs: String(value[0]), labels: safeLogMetadata({ ...(stream.stream || {}), ...(value[2] || {}) }) })));
    const aggregate = new Map();
    for (const row of rows) {
        const key = JSON.stringify(row.labels); aggregate.set(key, (aggregate.get(key) || 0) + 1);
    }
    const related = { traceId: options.traceRef, count: rows.length, groups: [...aggregate].map(([labels, count]) => ({ labels: JSON.parse(labels), count })).slice(0, 20), queriedAt: new Date().toISOString(), responseBytes: budget.bytes };
    report.relatedLogs = [...(report.relatedLogs || []).filter((row) => row.traceId !== options.traceRef), related].slice(0, LIMITS.maxTraces);
    report.source.relatedLogEndpointRef = digest(loki.origin);
    writeSummary(options.artifactDir, report);
    return related;
}

function artifactRoot() { return path.resolve(process.cwd(), ARTIFACT_ROOT); }
function validateArtifactRoot({ create = false } = {}) {
    const root = artifactRoot();
    if (!fs.existsSync(root) && create) fs.mkdirSync(root, { recursive: true, mode: 0o700 });
    if (!fs.existsSync(root)) return root;
    const stat = fs.lstatSync(root);
    if (!stat.isDirectory() || stat.isSymbolicLink() || (stat.mode & 0o077) !== 0) throw new Error('observability query artifact root must be a private regular directory');
    return root;
}
export function resolveQueryArtifactDirectory(input, { root = process.cwd() } = {}) {
    const requested = path.resolve(root, input);
    const productionRoot = path.resolve(root, ARTIFACT_ROOT);
    if (requested.startsWith(`${productionRoot}${path.sep}`)) return requested;
    const aliasRoot = path.resolve(root, '.pi/tmp');
    if (!requested.startsWith(`${aliasRoot}${path.sep}`)) return null;
    if (fs.existsSync(productionRoot) && fs.existsSync(requested)) {
        const canonicalRoot = fs.realpathSync(productionRoot); const canonicalRequested = fs.realpathSync(requested);
        if (canonicalRequested.startsWith(`${canonicalRoot}${path.sep}`)) return path.join(productionRoot, path.relative(canonicalRoot, canonicalRequested));
    }
    return null;
}
function ensureArtifactPath(input) {
    const root = artifactRoot(); const resolved = path.resolve(input);
    if (!(resolved === root || resolved.startsWith(`${root}${path.sep}`))) throw new Error(`artifact path must be below ${ARTIFACT_ROOT}`);
    if (fs.existsSync(resolved)) {
        const canonical = fs.realpathSync(resolved); const canonicalRoot = fs.existsSync(root) ? fs.realpathSync(root) : root;
        if (!(canonical === canonicalRoot || canonical.startsWith(`${canonicalRoot}${path.sep}`))) throw new Error('artifact symlink escapes the approved observability query root');
        return canonical;
    }
    return resolved;
}
export function readQuerySummary(directory) {
    const requestedDirectory = path.resolve(directory);
    const existedBeforeCleanup = fs.existsSync(requestedDirectory);
    cleanupExpiredArtifacts();
    if (existedBeforeCleanup && !fs.existsSync(requestedDirectory)) throw new Error('observability query artifact expired and was removed');
    const safeDirectory = ensureArtifactPath(directory);
    if (!fs.existsSync(safeDirectory)) throw new Error('bounded production artifact directory is missing');
    const relative = path.relative(artifactRoot(), safeDirectory);
    if (!relative || relative.startsWith('..')) throw new Error('artifact must identify one bounded production query run');
    const artifactDirectory = path.join(artifactRoot(), relative.split(path.sep)[0]);
    const privateDirectories = [artifactRoot()];
    let currentDirectory = artifactRoot();
    for (const component of relative.split(path.sep)) { currentDirectory = path.join(currentDirectory, component); privateDirectories.push(currentDirectory); }
    for (const privateDirectory of privateDirectories) {
        const directoryStat = fs.lstatSync(privateDirectory);
        if (!directoryStat.isDirectory() || directoryStat.isSymbolicLink() || (directoryStat.mode & 0o077) !== 0) throw new Error('observability query artifact directories must be private');
    }
    const provenanceFile = path.join(artifactDirectory, 'query-provenance.json');
    if (!fs.existsSync(provenanceFile)) throw new Error('observability query artifact is missing required provenance');
    const provenanceStat = fs.lstatSync(provenanceFile);
    if (!provenanceStat.isFile() || provenanceStat.isSymbolicLink() || (provenanceStat.mode & 0o077) !== 0) throw new Error('observability query provenance must be a regular private file');
    let provenanceDocument;
    try { provenanceDocument = JSON.parse(fs.readFileSync(provenanceFile, 'utf8')); } catch { throw new Error('observability query provenance is malformed'); }
    const created = Date.parse(provenanceDocument.createdAt); const expiry = Date.parse(provenanceDocument.expiresAt); const now = Date.now();
    if (provenanceDocument.schemaVersion !== 'bepis.otel.query-provenance.v1' || !['recent', 'comparison'].includes(provenanceDocument.command) || !['development', 'production'].includes(provenanceDocument.target) || provenanceDocument.containsCustomerData !== false || !Number.isFinite(created) || !Number.isFinite(expiry) || created > now + 60_000 || expiry <= created || expiry - created > LIMITS.artifactLifetimeHours * 3_600_000) throw new Error('observability query provenance is invalid');
    if (expiry < now) { fs.rmSync(artifactDirectory, { recursive: true, force: true }); throw new Error('observability query artifact expired and was removed'); }
    const file = path.join(safeDirectory, 'otel-summary.json');
    const stat = fs.lstatSync(file); if (!stat.isFile() || stat.isSymbolicLink() || (stat.mode & 0o077) !== 0 || stat.size > 4 * 1024 * 1024) throw new Error('bounded observability summary is missing, unsafe, or oversized');
    const report = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (report.schemaVersion !== 'bepis.otel.profile.v2' || report.source?.target !== provenanceDocument.target) throw new Error('unsupported or target-mismatched observability query artifact schema');
    return report;
}
function writePrivateJson(file, value) {
    const temporary = `${file}.tmp-${process.pid}`;
    const content = `${JSON.stringify(value, null, 2)}\n`;
    if (Buffer.byteLength(content) > 4 * 1024 * 1024) throw new Error('observability query artifact exceeded 4194304 byte limit');
    fs.writeFileSync(temporary, content, { mode: 0o600 }); fs.renameSync(temporary, file); fs.chmodSync(file, 0o600);
}
function writeSummary(directory, report) { writePrivateJson(path.join(ensureArtifactPath(directory), 'otel-summary.json'), report); }
function cleanupExpiredArtifacts(now = Date.now()) {
    const root = validateArtifactRoot(); if (!fs.existsSync(root)) return;
    for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
        if (!entry.isDirectory() || entry.isSymbolicLink()) continue;
        const directory = path.join(root, entry.name); const manifest = path.join(directory, 'query-provenance.json');
        try { if (Date.parse(JSON.parse(fs.readFileSync(manifest, 'utf8')).expiresAt) < now) fs.rmSync(directory, { recursive: true, force: true }); } catch { /* unknown artifacts are never deleted */ }
    }
}
function createArtifactDirectory(label, now = Date.now()) {
    cleanupExpiredArtifacts(now); const root = validateArtifactRoot({ create: true });
    const name = `${new Date(now).toISOString().replaceAll(':', '').replaceAll('.', '-')}-${label}-${randomBytes(4).toString('hex')}`;
    const directory = path.join(root, name); fs.mkdirSync(directory, { mode: 0o700 }); return directory;
}
function provenance(command, target, now = Date.now()) {
    return { schemaVersion: 'bepis.otel.query-provenance.v1', command, target, createdAt: new Date(now).toISOString(), expiresAt: new Date(now + LIMITS.artifactLifetimeHours * 3_600_000).toISOString(), containsCustomerData: false };
}
export function materializeReport(report, label = 'recent') {
    const directory = createArtifactDirectory(label);
    try {
        writePrivateJson(path.join(directory, 'otel-summary.json'), report);
        writePrivateJson(path.join(directory, 'query-provenance.json'), provenance(label, report.source?.target || 'development'));
        return directory;
    } catch (error) { fs.rmSync(directory, { recursive: true, force: true }); throw error; }
}
export function inspectTrace(options) {
    if (!/^[0-9a-f]{32}$/.test(options.traceRef || '')) throw new Error('--trace-ref must be a 32-character safe trace reference');
    const report = readQuerySummary(options.artifactDir); const trace = (report.traceViews || []).find((row) => row.traceId === options.traceRef);
    if (!trace) throw new Error('safe trace reference was not found in the bounded artifact');
    const limit = boundedInteger(options.spanLimit ?? 80, '--span-limit', 1, 200);
    return { traceId: trace.traceId, rootName: trace.rootName, rootDurationMs: trace.rootDurationMs, totalSpanCount: trace.spanCount, spans: trace.spans.slice(0, limit), relatedLogs: (report.relatedLogs || []).find((row) => row.traceId === trace.traceId) || null };
}
export async function compareWindows(options, dependencies = {}) {
    const minutes = boundedInteger(options.minutes ?? 5, '--minutes', 1, LIMITS.maxWindowMinutes);
    const beforeEnd = parseInstant(options.beforeEnd, '--before-end'); const afterEnd = parseInstant(options.afterEnd, '--after-end');
    const shared = { tempoUrl: options.tempoUrl, serviceName: options.serviceName, target: options.target, minutes, limit: options.limit };
    const before = await queryRecent({ ...shared, end: beforeEnd }, dependencies);
    const after = await queryRecent({ ...shared, end: afterEnd }, dependencies);
    const comparison = compareOtelProfiles(before, after);
    comparison.context = { ...comparison.context, deployments: { before: before.deployments, after: after.deployments } };
    const directory = createArtifactDirectory('comparison');
    try {
        const beforeDir = path.join(directory, 'before'); const afterDir = path.join(directory, 'after'); fs.mkdirSync(beforeDir, { mode: 0o700 }); fs.mkdirSync(afterDir, { mode: 0o700 });
        writePrivateJson(path.join(beforeDir, 'otel-summary.json'), before); writePrivateJson(path.join(afterDir, 'otel-summary.json'), after);
        writePrivateJson(path.join(directory, 'comparison.json'), comparison); writePrivateJson(path.join(directory, 'query-provenance.json'), provenance('comparison', options.target || 'production'));
        return { directory, comparison };
    } catch (error) { fs.rmSync(directory, { recursive: true, force: true }); throw error; }
}

function parseArgs(argv) {
    const options = {}; const args = [...argv];
    while (args.length) {
        const argument = args.shift(); const [flag, inline] = argument.includes('=') ? argument.split(/=(.*)/s, 2) : [argument, null];
        if (!flag.startsWith('--')) throw new Error(`unknown argument: ${argument}`);
        options[flag.slice(2).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())] = inline ?? args.shift();
    }
    return options;
}
function usage(command) {
    const lines = {
        recent: 'otel-recent [--target development|production] [--minutes 1..15] [--limit 1..20] [--end ISO-8601]',
        trace: 'otel-trace --artifact-dir .pi/tmp/observability-query/... --trace-ref SAFE_REF [--span-limit 1..200]',
        logs: 'otel-logs --artifact-dir .pi/tmp/observability-query/... --trace-ref SAFE_REF',
        compare: 'otel-compare [--target development|production] --before-end ISO-8601 --after-end ISO-8601 [--minutes 1..15] [--limit 1..20]',
    }; console.log(lines[command] || Object.values(lines).join('\n'));
}
export async function main(argv = process.argv.slice(2), environment = process.env) {
    cleanupExpiredArtifacts();
    const command = argv.shift(); if (!command || argv.includes('--help')) { usage(command); return; }
    const options = parseArgs(argv);
    const requestedTarget = options.target || environment.BEPIS_OTEL_QUERY_TARGET || 'development';
    if (command === 'recent') {
        const target = resolveQueryTarget(requestedTarget, environment);
        const report = await queryRecent({ ...options, target: target.target, serviceName: target.serviceName, tempoUrl: target.tempoUrl }, { allowLoopback: target.target === 'development', expectedPort: target.tempoUrl.port });
        const directory = materializeReport(report); console.log(JSON.stringify({ target: target.target, artifactDir: path.relative(process.cwd(), directory), summary: report.summary, slowestSpans: report.slowestSpans.slice(0, 10) }, null, 2));
    } else if (command === 'trace') console.log(JSON.stringify(inspectTrace(options), null, 2));
    else if (command === 'logs') {
        const report = readQuerySummary(options.artifactDir); const target = resolveQueryTarget(report.source.target, environment);
        if (!target.lokiUrl) throw new Error(`${target.target} target has no configured Loki query endpoint`);
        console.log(JSON.stringify(await queryRelatedLogs({ ...options, serviceName: target.serviceName, lokiUrl: target.lokiUrl }, { allowLoopback: target.target === 'development', expectedPort: target.lokiUrl.port }), null, 2));
    } else if (command === 'compare') {
        const target = resolveQueryTarget(requestedTarget, environment);
        const result = await compareWindows({ ...options, target: target.target, serviceName: target.serviceName, tempoUrl: target.tempoUrl }, { allowLoopback: target.target === 'development', expectedPort: target.tempoUrl.port });
        console.log(JSON.stringify({ artifactDir: path.relative(process.cwd(), result.directory), context: result.comparison.context, failures: result.comparison.failures, spans: result.comparison.spans.slice(0, 20), routes: result.comparison.routes.slice(0, 20) }, null, 2));
    } else throw new Error(`unknown observability query command: ${command}`);
}
if (import.meta.url === `file://${process.argv[1]}`) main().catch((error) => { console.error(`Observability query failed: ${String(error.message || error).slice(0, 300)}`); process.exit(1); });
