import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { LIMITS, compareWindows, inspectTrace, materializeReport, queryRecent, queryRelatedLogs, resolveQueryArtifactDirectory, resolveQueryTarget, validateQueryEndpoint } from './query.mjs';

const rawTraceId = '0123456789abcdef0123456789abcdef';
const now = Date.now();
const startNs = BigInt(now - 1_000) * 1_000_000n;
const endNs = BigInt(now) * 1_000_000n;
const attr = (key, value) => ({ key, value: typeof value === 'number' ? { intValue: String(value) } : { stringValue: String(value) } });
const traceDocument = {
    batches: [{
        resource: { attributes: [attr('service.name', 'ihp-roster'), attr('service.version', 'abc1234'), attr('private.customer', 'Alice')] },
        scopeSpans: [{ spans: [
            { traceId: rawTraceId, spanId: '1111111111111111', name: 'RosterWeeksAction', startTimeUnixNano: String(startNs), endTimeUnixNano: String(endNs), attributes: [attr('bepis.ihp.action', 'RosterWeeksAction'), attr('http.request.method', 'GET'), attr('customer.email', 'alice@example.com')] },
            { traceId: rawTraceId, spanId: 'alice@example.com', parentSpanId: '1111111111111111', name: 'alice@example.com private payload', startTimeUnixNano: String(startNs + 1n), endTimeUnixNano: String(endNs - 1n), status: { code: 'STATUS_CODE_ERROR', message: 'secret transport alice@example.com' }, attributes: [attr('db.system', 'postgresql'), attr('db.statement', 'select private')] },
        ] }],
    }],
};

function jsonResponse(value, init = {}) { return new Response(JSON.stringify(value), { status: 200, headers: { 'content-type': 'application/json' }, ...init }); }
function tempoFetch(calls) {
    return async (input, init) => {
        const url = new URL(input); calls.push({ url, init });
        if (url.pathname === '/api/search') return jsonResponse({ traces: [{ traceID: rawTraceId }] });
        if (url.pathname === `/api/traces/${rawTraceId}`) return jsonResponse(traceDocument);
        return new Response('missing', { status: 404 });
    };
}

function removeArtifact(directory) { fs.rmSync(directory, { recursive: true, force: true }); }

test('query endpoints accept only configured tailnet origins and read ports', () => {
    assert.equal(validateQueryEndpoint('https://bepis-prod.example.ts.net:3200', 'tempo').port, '3200');
    assert.equal(validateQueryEndpoint('http://100.64.12.4:3101', 'loki').port, '3101');
    assert.throws(() => validateQueryEndpoint('https://example.com:3200', 'tempo'), /not an approved tailnet/);
    assert.throws(() => validateQueryEndpoint('https://bepis.ts.net:4318', 'tempo'), /query port 3200/);
    assert.throws(() => validateQueryEndpoint('https://bepis.ts.net:3200/api/search', 'tempo'), /without credentials, path/);
    assert.throws(() => validateQueryEndpoint('https://user:secret@bepis.ts.net:3200', 'tempo'), /without credentials/);
    assert.throws(() => validateQueryEndpoint('http://127.0.0.1:3200', 'tempo'), /not an approved tailnet/);
    assert.equal(validateQueryEndpoint('http://127.0.0.1:3200', 'tempo', { allowLoopback: true }).hostname, '127.0.0.1');
    assert.throws(() => validateQueryEndpoint('https://bepis.ts.net:3200', 'tempo', { allowLoopback: true }), /not an approved loopback/);
});

test('generic target selection defaults to the current local workspace and requires explicit production configuration', () => {
    const development = resolveQueryTarget(undefined, { IHP_ROSTER_DEV_TEMPO_PORT: '3210', BEPIS_WORKSPACE_OTEL_SERVICE_NAME: 'ihp-roster-dev-slot-10' });
    assert.equal(development.target, 'development');
    assert.equal(development.tempoUrl.href, 'http://127.0.0.1:3210/');
    assert.equal(development.serviceName, 'ihp-roster-dev-slot-10');
    assert.equal(development.lokiUrl, null);
    assert.throws(() => resolveQueryTarget('development', { IHP_ROSTER_DEV_TEMPO_PORT: '3200', BEPIS_DEVELOPMENT_TEMPO_QUERY_URL: 'http://127.0.0.1:4318' }), /query port 3200/);
    assert.throws(() => resolveQueryTarget('production', {}), /Missing configured tempo query endpoint/);
    const production = resolveQueryTarget('production', { BEPIS_PRODUCTION_TEMPO_QUERY_URL: 'https://bepis.ts.net:3200', BEPIS_PRODUCTION_LOKI_QUERY_URL: 'https://bepis.ts.net:3101' });
    assert.equal(production.target, 'production');
    assert.equal(production.serviceName, 'ihp-roster');
    assert.equal(production.lokiUrl.port, '3101');
});

test('artifact provenance binds follow-up inspection to its original target', async () => {
    const report = await queryRecent({ tempoUrl: 'http://127.0.0.1:3200', target: 'development', serviceName: 'ihp-roster-dev-slot-10', minutes: 5, end: now, limit: 1 }, { allowLoopback: true, fetchImpl: tempoFetch([]) });
    const directory = materializeReport(report);
    try {
        const provenance = JSON.parse(fs.readFileSync(path.join(directory, 'query-provenance.json')));
        assert.equal(provenance.target, 'development');
        assert.equal(inspectTrace({ artifactDir: directory, traceRef: report.traceWindows[0].traceId }).totalSpanCount, 2);
        const summaryPath = path.join(directory, 'otel-summary.json'); const mismatched = JSON.parse(fs.readFileSync(summaryPath)); mismatched.source.target = 'production'; fs.writeFileSync(summaryPath, JSON.stringify(mismatched));
        assert.throws(() => inspectTrace({ artifactDir: directory, traceRef: report.traceWindows[0].traceId }), /target-mismatched/);
    } finally { removeArtifact(directory); }
});

test('recent query is time/row bounded and materializes only the safe common model', async () => {
    const calls = [];
    const report = await queryRecent({ tempoUrl: 'http://127.0.0.1:3200', minutes: 5, end: now, limit: 3 }, { allowLoopback: true, fetchImpl: tempoFetch(calls) });
    assert.equal(report.schemaVersion, 'bepis.otel.profile.v2');
    assert.equal(report.summary.traceCount, 1);
    assert.equal(report.summary.spanCount, 2);
    assert.equal(report.traceWindows.length, 1);
    assert.deepEqual(report.deployments, [{ version: 'abc1234', slot: 'unknown' }]);
    assert.match(report.traceWindows[0].traceId, /^[0-9a-f]{32}$/);
    assert.equal(calls.length, 2);
    assert.ok(calls.every((call) => call.init.method === 'GET'));
    assert.equal(calls[0].url.pathname, '/api/search');
    assert.equal(calls[1].url.pathname, `/api/traces/${rawTraceId}`);
    assert.ok(calls.every((call) => !/4317|4318|4327|4328|\/otlp/.test(call.url.href)));
    assert.equal(calls[0].url.searchParams.get('tags'), 'service.name=ihp-roster');
    assert.equal(calls[0].url.searchParams.get('limit'), '3');
    assert.ok(Number(calls[0].url.searchParams.get('end')) - Number(calls[0].url.searchParams.get('start')) <= 300);
    const serialized = JSON.stringify(report);
    assert.doesNotMatch(serialized, /alice|private payload|secret transport|select private/i);
    assert.doesNotMatch(serialized, new RegExp(rawTraceId));
    assert.match(serialized, /span:[0-9a-f]{16}/);
    assert.match(serialized, /RosterWeeksAction/);

    const directory = materializeReport(report);
    const alias = path.join(process.cwd(), '.pi', 'tmp', `observability-query-alias-${process.pid}`);
    const outsideAlias = path.join('/tmp', `observability-query-alias-${process.pid}`);
    fs.rmSync(alias, { force: true }); fs.rmSync(outsideAlias, { force: true });
    fs.symlinkSync(directory, alias); fs.symlinkSync(directory, outsideAlias);
    try {
        assert.equal(resolveQueryArtifactDirectory(alias), directory);
        assert.equal(resolveQueryArtifactDirectory(outsideAlias), null);
        const trace = inspectTrace({ artifactDir: directory, traceRef: report.traceWindows[0].traceId, spanLimit: 1 });
        assert.equal(trace.spans.length, 1);
        assert.equal(trace.totalSpanCount, 2);
        const mode = fs.statSync(path.join(directory, 'otel-summary.json')).mode & 0o777;
        assert.equal(mode, 0o600);
        const provenance = JSON.parse(fs.readFileSync(path.join(directory, 'query-provenance.json')));
        assert.equal(provenance.containsCustomerData, false);
        assert.ok(Date.parse(provenance.expiresAt) - Date.parse(provenance.createdAt) <= LIMITS.artifactLifetimeHours * 3_600_000);
        const root = path.dirname(directory); fs.chmodSync(root, 0o755);
        try { assert.throws(() => inspectTrace({ artifactDir: directory, traceRef: report.traceWindows[0].traceId }), /artifact root must be a private regular directory/); }
        finally { fs.chmodSync(root, 0o700); }
    } finally { fs.rmSync(alias, { force: true }); fs.rmSync(outsideAlias, { force: true }); removeArtifact(directory); }
});

test('related logs use one fixed Loki GET query and retain only redacted aggregates', async () => {
    const calls = [];
    const report = await queryRecent({ tempoUrl: 'http://127.0.0.1:3200', minutes: 5, end: now, limit: 1 }, { allowLoopback: true, fetchImpl: tempoFetch([]) });
    const directory = materializeReport(report);
    try {
        const result = await queryRelatedLogs({ lokiUrl: 'http://127.0.0.1:3101', artifactDir: directory, traceRef: report.traceWindows[0].traceId }, {
            allowLoopback: true,
            fetchImpl: async (input, init) => {
                calls.push({ url: new URL(input), init });
                return jsonResponse({ data: { result: [{ stream: { service_name: 'ihp-roster', forbidden: 'alice@example.com' }, values: [[String(startNs), '[redacted production journal event]', { systemd_unit: 'app.service', forbidden: 'secret' }]] }] } });
            },
        });
        assert.equal(result.count, 1);
        assert.deepEqual(result.groups, [{ labels: { systemd_unit: 'app.service' }, count: 1 }]);
        assert.equal(calls[0].init.method, 'GET');
        assert.equal(calls[0].url.pathname, '/loki/api/v1/query_range');
        assert.equal(calls[0].url.searchParams.get('query'), '{service_name="ihp-roster"}');
        assert.equal(calls[0].url.searchParams.get('limit'), String(LIMITS.maxLogRows));
        assert.doesNotMatch(fs.readFileSync(path.join(directory, 'otel-summary.json'), 'utf8'), /alice|secret/i);
        assert.equal(inspectTrace({ artifactDir: directory, traceRef: report.traceWindows[0].traceId }).relatedLogs.count, 1);
    } finally { removeArtifact(directory); }
});

test('unsafe Loki content and unsafe artifact paths fail closed without persisting payloads', async () => {
    const report = await queryRecent({ tempoUrl: 'http://127.0.0.1:3200', minutes: 5, end: now, limit: 1 }, { allowLoopback: true, fetchImpl: tempoFetch([]) });
    const directory = materializeReport(report); const original = fs.readFileSync(path.join(directory, 'otel-summary.json'), 'utf8');
    try {
        await assert.rejects(() => queryRelatedLogs({ lokiUrl: 'http://127.0.0.1:3101', artifactDir: directory, traceRef: report.traceWindows[0].traceId }, {
            allowLoopback: true,
            fetchImpl: async () => jsonResponse({ data: { result: [{ values: [[String(startNs), 'customer alice@example.com']] }] } }),
        }), /non-redacted log content/);
        assert.equal(fs.readFileSync(path.join(directory, 'otel-summary.json'), 'utf8'), original);
        const redactedRows = Array.from({ length: LIMITS.maxLogRows }, (_, index) => [String(startNs + BigInt(index)), '[redacted production journal event]']);
        await assert.rejects(() => queryRelatedLogs({ lokiUrl: 'http://127.0.0.1:3101', artifactDir: directory, traceRef: report.traceWindows[0].traceId }, {
            allowLoopback: true,
            fetchImpl: async () => jsonResponse({ data: { result: [{ values: [...redactedRows, [String(endNs - 1n), '[redacted production journal event]'], [String(endNs), 'late private payload']] }] } }),
        }), /non-redacted log content/);
        await assert.rejects(() => queryRelatedLogs({ lokiUrl: 'http://127.0.0.1:3101', artifactDir: directory, traceRef: report.traceWindows[0].traceId }, {
            allowLoopback: true,
            fetchImpl: async () => jsonResponse({ data: { result: [{ values: [...redactedRows, [String(endNs), '[redacted production journal event]']] }] } }),
        }), /more than 200 bounded log rows/);
        assert.equal(fs.readFileSync(path.join(directory, 'otel-summary.json'), 'utf8'), original);
        assert.throws(() => inspectTrace({ artifactDir: '/tmp', traceRef: report.traceWindows[0].traceId }), /must be below/);
        fs.unlinkSync(path.join(directory, 'otel-summary.json')); fs.symlinkSync('/etc/passwd', path.join(directory, 'otel-summary.json'));
        assert.throws(() => inspectTrace({ artifactDir: directory, traceRef: report.traceWindows[0].traceId }), /missing, unsafe, or oversized/);
    } finally { removeArtifact(directory); }
});

test('limits, authorization, backend outages, and byte ceilings return concise diagnostics', async () => {
    await assert.rejects(() => queryRecent({ tempoUrl: 'http://127.0.0.1:3200', minutes: 16, end: now, limit: 1 }, { allowLoopback: true, fetchImpl: tempoFetch([]) }), /1 to 15/);
    await assert.rejects(() => queryRecent({ tempoUrl: 'http://127.0.0.1:3200', minutes: 1, end: now, limit: 21 }, { allowLoopback: true, fetchImpl: tempoFetch([]) }), /1 to 20/);
    await assert.rejects(() => queryRecent({ tempoUrl: 'http://127.0.0.1:3200', minutes: 1, end: now, limit: 1 }, { allowLoopback: true, fetchImpl: async () => new Response('', { status: 403 }) }), /^Error: Tempo authorization failed$/);
    await assert.rejects(() => queryRecent({ tempoUrl: 'http://127.0.0.1:3200', minutes: 1, end: now, limit: 1 }, { allowLoopback: true, fetchImpl: async () => { throw new Error('connect ECONNREFUSED 10.0.0.1 private'); } }), /^Error: Tempo backend unavailable$/);
    await assert.rejects(() => queryRecent({ tempoUrl: 'http://127.0.0.1:3200', minutes: 1, end: now, limit: 1 }, { allowLoopback: true, fetchImpl: async () => new Response('{}', { headers: { 'content-length': String(LIMITS.maxResponseBytes + 1) } }) }), /response exceeded/);
});

test('every artifact read cleans unrelated expired runs and requires private provenance', async () => {
    const report = await queryRecent({ tempoUrl: 'http://127.0.0.1:3200', minutes: 5, end: now, limit: 1 }, { allowLoopback: true, fetchImpl: tempoFetch([]) });
    const expiredDirectory = materializeReport(report); const activeDirectory = materializeReport(report);
    const manifestPath = path.join(expiredDirectory, 'query-provenance.json');
    const manifest = JSON.parse(fs.readFileSync(manifestPath)); manifest.expiresAt = '2000-01-01T00:00:00.000Z'; fs.writeFileSync(manifestPath, JSON.stringify(manifest));
    try {
        assert.equal(inspectTrace({ artifactDir: activeDirectory, traceRef: report.traceWindows[0].traceId }).totalSpanCount, 2);
        assert.equal(fs.existsSync(expiredDirectory), false);
        fs.chmodSync(path.join(activeDirectory, 'query-provenance.json'), 0o644);
        assert.throws(() => inspectTrace({ artifactDir: activeDirectory, traceRef: report.traceWindows[0].traceId }), /regular private file/);
        fs.chmodSync(path.join(activeDirectory, 'query-provenance.json'), 0o600);
        fs.unlinkSync(path.join(activeDirectory, 'query-provenance.json'));
        assert.throws(() => inspectTrace({ artifactDir: activeDirectory, traceRef: report.traceWindows[0].traceId }), /missing required provenance/);
    } finally { removeArtifact(activeDirectory); }
});

test('related-log windows cannot escape the seven-day production bound', async () => {
    const report = await queryRecent({ tempoUrl: 'http://127.0.0.1:3200', minutes: 5, end: now, limit: 1 }, { allowLoopback: true, fetchImpl: tempoFetch([]) });
    report.traceWindows[0].startNs = '1'; report.traceWindows[0].endNs = '2';
    const directory = materializeReport(report);
    try {
        await assert.rejects(() => queryRelatedLogs({ lokiUrl: 'http://127.0.0.1:3101', artifactDir: directory, traceRef: report.traceWindows[0].traceId }, { allowLoopback: true, fetchImpl: async () => { throw new Error('must not fetch'); } }), /within the last 7 days/);
    } finally { removeArtifact(directory); }
});

test('artifact creation rejects a symlinked query root before writing or cleanup', async () => {
    const report = await queryRecent({ tempoUrl: 'http://127.0.0.1:3200', target: 'development', serviceName: 'ihp-roster-dev', minutes: 1, end: now, limit: 1 }, { allowLoopback: true, fetchImpl: tempoFetch([]) });
    const root = path.join(process.cwd(), '.pi', 'tmp', 'observability-query'); const backup = `${root}-backup-${process.pid}`; const outside = fs.mkdtempSync(path.join('/tmp', 'observability-query-outside-'));
    fs.rmSync(backup, { recursive: true, force: true }); fs.renameSync(root, backup); fs.symlinkSync(outside, root);
    try {
        assert.throws(() => materializeReport(report), /artifact root must be a private regular directory/);
        assert.deepEqual(fs.readdirSync(outside), []);
    } finally { fs.unlinkSync(root); fs.renameSync(backup, root); fs.rmSync(outside, { recursive: true, force: true }); }
});

test('deployment comparison queries two bounded windows and emits the common comparison schema', async () => {
    const calls = [];
    const result = await compareWindows({ tempoUrl: 'http://127.0.0.1:3200', beforeEnd: new Date(now - 3_600_000).toISOString(), afterEnd: new Date(now).toISOString(), minutes: 5, limit: 2 }, { allowLoopback: true, fetchImpl: tempoFetch(calls) });
    try {
        assert.equal(result.comparison.schemaVersion, 'bepis.otel.comparison.v2');
        assert.equal(calls.filter((row) => row.url.pathname === '/api/search').length, 2);
        assert.ok(fs.existsSync(path.join(result.directory, 'before', 'otel-summary.json')));
        assert.ok(fs.existsSync(path.join(result.directory, 'after', 'otel-summary.json')));
        assert.ok(fs.existsSync(path.join(result.directory, 'comparison.json')));
        const beforeDir = path.join(result.directory, 'before'); const before = JSON.parse(fs.readFileSync(path.join(beforeDir, 'otel-summary.json')));
        fs.chmodSync(beforeDir, 0o755);
        try { assert.throws(() => inspectTrace({ artifactDir: beforeDir, traceRef: before.traceViews[0].traceId }), /directories must be private/); }
        finally { fs.chmodSync(beforeDir, 0o700); }
    } finally { removeArtifact(result.directory); }
});
