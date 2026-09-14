import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import { execFileSync } from 'node:child_process';
import test from 'node:test';
import { buildOtelSummary, normalizeOtelDocuments, OTEL_ARTIFACT_SCHEMA, readOtelArtifact, resolveAllowedArtifact, routeIdentity, summarizeOtelSpans, traceReference } from '../../e2e/otel-artifact.mjs';
import { compareOtelProfiles } from '../../e2e/profile-compare.mjs';
import { summarizeTempo } from '../../e2e/otel-trace-summary.mjs';

const attr = (key, value) => ({ key, value: typeof value === 'boolean' ? { boolValue: value } : { stringValue: String(value) } });
const span = ({ traceId = 'trace-1', spanId, parentSpanId = '', name, start, end, attrs = [], status }) => ({ traceId, spanId, parentSpanId, name, startTimeUnixNano: String(start * 1_000_000), endTimeUnixNano: String(end * 1_000_000), attributes: attrs, ...(status ? { status } : {}) });
const spans = [
    span({ spanId: 'root', name: 'http.request', start: 0, end: 100, attrs: [attr('http.route', '/RosterWeeks'), attr('http.request.method', 'GET'), attr('bepis.ihp.action', 'RosterWeeksAction')] }),
    span({ spanId: 'db1', parentSpanId: 'root', name: 'postgresql.query', start: 10, end: 50, attrs: [attr('db.system', 'postgresql')] }),
    span({ spanId: 'db2', parentSpanId: 'root', name: 'postgresql.query', start: 30, end: 70, attrs: [attr('db.system', 'postgresql')] }),
    span({ spanId: 'exit', parentSpanId: 'root', name: 'response.exit', start: 75, end: 80, status: { code: 'STATUS_CODE_ERROR', message: 'ResponseException' } }),
    span({ spanId: 'failure', parentSpanId: 'root', name: 'provider.request', start: 80, end: 90, status: { code: 'STATUS_CODE_ERROR', message: 'transport unavailable' }, attrs: [attr('bepis.provider.kind', 'xero')] }),
];
const collector = { resourceSpans: [{ resource: { attributes: [attr('service.name', 'bepis')] }, scopeSpans: [{ scope: { name: 'test' }, spans }] }] };
const tempo = { batches: [{ resource: { attributes: [attr('service.name', 'bepis')] }, scopeSpans: [{ scope: { name: 'test' }, spans }] }] };

test('collector and Tempo materializations produce the same versioned common model', () => {
    const collectorSummary = summarizeOtelSpans(normalizeOtelDocuments(collector));
    const tempoSummary = summarizeOtelSpans(normalizeOtelDocuments(tempo));
    assert.equal(collectorSummary.schemaVersion, OTEL_ARTIFACT_SCHEMA);
    assert.deepEqual(collectorSummary.summary, tempoSummary.summary);
    assert.deepEqual(collectorSummary.spanGroups, tempoSummary.spanGroups);
    assert.equal(collectorSummary.summary.statuses.ihpResponseExit, 1);
    assert.equal(collectorSummary.summary.statuses.error, 1);
    assert.equal(collectorSummary.traceViews[0].spans.find((row) => row.spanId === 'root').exclusiveMs, 25, 'overlapping and adjacent children are unioned');
    assert.equal(collectorSummary.categories.find((row) => row.category === 'database').durationMs.sampleCount, 2);
    assert.equal(collectorSummary.categories.find((row) => row.category === 'provider').durationMs.sampleCount, 1);
    const privateRoute = routeIdentity({ attributes: { 'http.target': '/Staff/123456?email=private@example.com' } }).route;
    assert.match(privateRoute, /^path:[0-9a-f]{16}$/);
    assert.doesNotMatch(privateRoute, /Staff|private|123456/);
    assert.equal(routeIdentity({ attributes: { 'http.route': 'ShowRosterWindowAction' } }).route, 'ShowRosterWindowAction');
    const unsafeIdentity = routeIdentity({ attributes: { 'http.route': '/Roster/{id}/Alice', 'bepis.ihp.action': 'alice@example.com' } });
    assert.match(unsafeIdentity.route, /^route:[0-9a-f]{16}$/);
    assert.match(unsafeIdentity.action, /^action:[0-9a-f]{16}$/);
    assert.doesNotMatch(JSON.stringify(unsafeIdentity), /Alice|alice@example/);
});

test('browser Tempo query materialization emits the same common schema', async () => {
    const server = http.createServer((request, response) => {
        response.setHeader('content-type', 'application/json');
        const tempoWithoutSpanIds = { batches: tempo.batches.map((batch) => ({ ...batch, scopeSpans: batch.scopeSpans.map((scope) => ({ ...scope, spans: scope.spans.map(({ traceId: _traceId, ...row }) => row) })) })) };
        response.end(JSON.stringify(request.url.startsWith('/api/search') ? { traces: [{ traceID: 'trace-1' }] } : tempoWithoutSpanIds));
    });
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    try {
        const address = server.address();
        const report = await summarizeTempo({ tempoUrl: `http://127.0.0.1:${address.port}`, service: 'test', runId: null, limit: 10, timeoutMs: 1_000 });
        assert.equal(report.schemaVersion, OTEL_ARTIFACT_SCHEMA);
        assert.equal(report.source.format, 'tempo-query-materialization');
        assert.equal(report.summary.spanCount, spans.length);
        assert.equal(report.traceViews[0].traceId, traceReference('trace-1'));
    } finally { await new Promise((resolve) => server.close(resolve)); }
});

test('exclusive time keeps parent-child identity scoped to each trace', () => {
    const colliding = normalizeOtelDocuments({ resourceSpans: [{ scopeSpans: [{ spans: [
        span({ traceId: 'a', spanId: 'root', name: 'a', start: 0, end: 100 }),
        span({ traceId: 'a', spanId: 'child', parentSpanId: 'root', name: 'child-a', start: 10, end: 20 }),
        span({ traceId: 'b', spanId: 'root', name: 'b', start: 0, end: 100 }),
        span({ traceId: 'b', spanId: 'child', parentSpanId: 'root', name: 'child-b', start: 30, end: 50 }),
    ] }] }] });
    const report = summarizeOtelSpans(colliding);
    assert.equal(report.traceViews.find((trace) => trace.rootName === 'a').spans.find((row) => row.spanId === 'root').exclusiveMs, 90);
    assert.equal(report.traceViews.find((trace) => trace.rootName === 'b').spans.find((row) => row.spanId === 'root').exclusiveMs, 80);
    assert.doesNotMatch(JSON.stringify(report.traceViews), /"traceId":"[ab]"/);
});

test('Tempo enforces the cumulative span cap while fetching multiple traces', async () => {
    const server = http.createServer((request, response) => {
        response.setHeader('content-type', 'application/json');
        response.end(JSON.stringify(request.url.startsWith('/api/search') ? { traces: [{ traceID: 'trace-1' }, { traceID: 'trace-2' }] } : tempo));
    });
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    try {
        const address = server.address();
        await assert.rejects(() => summarizeTempo({ tempoUrl: `http://127.0.0.1:${address.port}`, service: 'test', runId: null, limit: 10, timeoutMs: 1_000, maxSpans: 6 }), /exceeds 6 span limit/);
    } finally { await new Promise((resolve) => server.close(resolve)); }
});

test('comparison matches route/span identities with sample confidence and load pressure', () => {
    const before = summarizeOtelSpans(normalizeOtelDocuments(collector), { metadata: { loadPressure: { droppedIterations: 1, vuSaturation: 0.5 } } });
    const afterSpans = normalizeOtelDocuments(collector).map((row) => ({ ...row, endNs: String(BigInt(row.startNs) + BigInt(Math.round(row.durationMs * 2 * 1_000_000))), durationMs: row.durationMs * 2 }));
    const after = summarizeOtelSpans(afterSpans, { metadata: { loadPressure: { droppedIterations: 3, vuSaturation: 0.75 } } });
    const comparison = compareOtelProfiles(before, after);
    assert.equal(comparison.schemaVersion, 'bepis.otel.comparison.v2');
    assert.ok(comparison.spans.length >= 4);
    assert.equal(comparison.spans[0].confidence, 'low');
    assert.equal(comparison.loadPressure.droppedIterations.value, 2);
    assert.equal(comparison.loadPressure.vuSaturation.value, 0.3);
    assert.equal(comparison.failures.after.error, 1);
    assert.equal(comparison.failures.after.ihpResponseExit, 1);
});

test('comparison retains bounded compatibility with legacy load-suite summaries', () => {
    const legacy = { scenarios: [{ scenario: 'roster', summary: { spans: [{ route: '/Roster', span: 'render', count: 5, medianMs: 10, p95Ms: 20 }], http: [{ route: '/Roster', method: 'GET', count: 5, medianMs: 12, p95Ms: 24 }], droppedIterations: 1, vuSaturation: 0.5 } }] };
    const candidate = structuredClone(legacy); candidate.scenarios[0].summary.spans[0].p95Ms = 25;
    const comparison = compareOtelProfiles(legacy, candidate);
    assert.equal(comparison.spans.length, 1);
    assert.equal(comparison.spans[0].identity.scenario, 'roster');
    assert.equal(comparison.spans[0].p95Ms.value, 5);
    assert.equal(comparison.loadPressure.before.droppedIterations, 1);
});

test('suite wrapper reads only bounded common summaries below safe scenario paths', () => {
    const suiteDir = path.join(process.cwd(), 'output', `.otel-suite-test-${process.pid}`);
    const scenarioDir = path.join(suiteDir, 'roster');
    fs.mkdirSync(scenarioDir, { recursive: true });
    try {
        const report = summarizeOtelSpans(normalizeOtelDocuments(collector));
        fs.writeFileSync(path.join(scenarioDir, 'otel-summary.json'), JSON.stringify(report));
        execFileSync(process.execPath, ['e2e/otel-suite-summary.mjs', suiteDir, 'roster'], { cwd: process.cwd() });
        const suiteOutput = path.join(suiteDir, 'otel-summary.json');
        assert.equal(JSON.parse(fs.readFileSync(suiteOutput)).schemaVersion, 'bepis.otel.suite.v2');
        assert.throws(() => execFileSync(process.execPath, ['e2e/otel-suite-summary.mjs', suiteDir, '../private'], { cwd: process.cwd(), stdio: 'pipe' }), /Command failed/);
        assert.throws(() => execFileSync(process.execPath, ['e2e/otel-suite-summary.mjs', suiteDir, ...Array.from({ length: 21 }, (_, index) => `scenario-${index}`)], { cwd: process.cwd(), stdio: 'pipe' }), /Command failed/);
        const outsideTarget = path.join(os.tmpdir(), `otel-suite-outside-${process.pid}.json`); fs.writeFileSync(outsideTarget, 'unchanged');
        fs.unlinkSync(suiteOutput); fs.symlinkSync(outsideTarget, suiteOutput);
        assert.throws(() => execFileSync(process.execPath, ['e2e/otel-suite-summary.mjs', suiteDir, 'roster'], { cwd: process.cwd(), stdio: 'pipe' }), /Command failed/);
        assert.equal(fs.readFileSync(outsideTarget, 'utf8'), 'unchanged'); fs.rmSync(outsideTarget, { force: true });
        fs.unlinkSync(suiteOutput);
        const danglingTarget = path.join(os.tmpdir(), `otel-suite-dangling-${process.pid}.json`); fs.rmSync(danglingTarget, { force: true });
        fs.symlinkSync(danglingTarget, suiteOutput);
        assert.throws(() => execFileSync(process.execPath, ['e2e/otel-suite-summary.mjs', suiteDir, 'roster'], { cwd: process.cwd(), stdio: 'pipe' }), /Command failed/);
        assert.equal(fs.existsSync(danglingTarget), false);
    } finally { fs.rmSync(suiteDir, { recursive: true, force: true }); }
});

test('artifact parser rejects malformed, oversized, over-span, and unsafe inputs with bounded diagnostics', () => {
    const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'otel-artifact-'));
    try {
        const malformed = path.join(temp, 'malformed.json'); fs.writeFileSync(malformed, '{nope');
        assert.throws(() => readOtelArtifact(malformed), /Malformed OpenTelemetry JSON/);
        const oversized = path.join(temp, 'oversized.json'); fs.writeFileSync(oversized, '123456');
        assert.throws(() => readOtelArtifact(oversized, { maxBytes: 5 }), /exceeds 5 byte limit/);
        assert.throws(() => normalizeOtelDocuments(collector, { maxSpans: 2 }), /exceeds 2 span limit/);
        assert.throws(() => summarizeOtelSpans(normalizeOtelDocuments(collector), { limits: { maxSpans: 2 } }), /exceeds 2 span limit/);
        const oversizedTraceId = 'private@example.com'.repeat(1000);
        let boundedError;
        try { summarizeOtelSpans([{ ...normalizeOtelDocuments(collector)[0], traceId: oversizedTraceId }, { ...normalizeOtelDocuments(collector)[1], traceId: oversizedTraceId }], { limits: { maxSpansPerTrace: 1 } }); } catch (error) { boundedError = error; }
        assert.match(boundedError.message, /^Trace ref [0-9a-f]{16} exceeds 1 span view limit$/);
        assert.ok(boundedError.message.length < 80);
        assert.doesNotMatch(boundedError.message, /private/);
        assert.throws(() => resolveAllowedArtifact('/etc/passwd', { root: temp }), /Unsafe artifact path/);
        fs.mkdirSync(path.join(temp, 'output')); fs.symlinkSync('/etc/passwd', path.join(temp, 'output', 'escape'));
        assert.throws(() => resolveAllowedArtifact('output/escape', { root: temp }), /Unsafe artifact symlink/);
    } finally { fs.rmSync(temp, { recursive: true, force: true }); }
});

test('file summary retains bounded source context and safe trace views', () => {
    const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'otel-summary-'));
    try {
        const input = path.join(temp, 'otel.json'); fs.writeFileSync(input, `${JSON.stringify(collector)}\n`);
        const report = buildOtelSummary(input, { metadata: { scenario: 'test' } });
        assert.equal(report.context.scenario, 'test');
        assert.equal(report.source.format, 'collector-file-export');
        assert.deepEqual(Object.keys(report.traceViews[0].spans[0]).sort(), ['action', 'category', 'durationMs', 'exclusiveMs', 'method', 'name', 'parentSpanId', 'route', 'spanId', 'status', 'traceId'].sort());
    } finally { fs.rmSync(temp, { recursive: true, force: true }); }
});
