import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const repoRoot = path.resolve(import.meta.dirname, '../..');

test('primary profile reporters do not consume retired X-Profile headers', () => {
  for (const relativePath of ['e2e/profile-app.mjs', 'e2e/profile-load.js', 'e2e/profile-load-report.mjs', 'e2e/profile-load-suite-report.mjs']) {
    const source = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
    assert.doesNotMatch(source, /x-profile-(?:counters|response-bytes)|profile_counter_value/i, relativePath);
  }
});

test('profile scenario catalog covers diagnostic roles and operations', () => {
  const catalog = JSON.parse(fs.readFileSync(path.join(repoRoot, 'e2e/profile-scenarios.json'), 'utf8'));
  for (const name of ['staff', 'support', 'billing', 'auth', 'writes']) {
    assert.ok(catalog.browserScenarios[name]?.length > 0, `missing browser scenario ${name}`);
  }
  for (const name of ['staff', 'support', 'billing', 'auth']) {
    assert.ok(catalog.loadScenarios[name]?.length > 0, `missing load scenario ${name}`);
  }
  assert.ok(catalog.browserScenarios.support.some((entry) => entry.kind === 'jobEnqueue'));
  assert.ok(catalog.browserScenarios.auth.some((entry) => entry.kind === 'passwordLogin'));
  assert.ok(catalog.browserScenarios.auth.some((entry) => entry.kind === 'passkeyRegistration'));
  assert.ok(catalog.browserScenarios.writes.some((entry) => entry.kind === 'exportGeneration'));
  const liveSource = fs.readFileSync(path.join(repoRoot, 'e2e/profile-live-load.js'), 'utf8');
  assert.doesNotMatch(liveSource, /fragments:\s*\[\]/);
  for (const fragment of ['support-award-rates', 'admin-invites', 'timesheet-toolbar', 'roster-day-columns', 'leave-section-list']) {
    assert.match(liveSource, new RegExp(fragment));
  }
});

test('diagnostic profile bounds fingerprints and weighted live aggregates', () => {
  const outputDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bepis-diagnostic-profile-bounds-'));
  try {
    const alpha = (index) => {
      let value = index;
      let result = '';
      do { result = String.fromCharCode(97 + (value % 26)) + result; value = Math.floor(value / 26) - 1; } while (value >= 0);
      return result;
    };
    fs.writeFileSync(path.join(outputDir, 'server.log'), [
      ...Array.from({ length: 300 }, (_, index) => `🔍 SELECT column_${alpha(index)} FROM profile_table (${index % 20}ms)`),
      '[diagnostic-runtime] {"allocatedBytes":1,"copiedBytes":1,"gcCount":1,"majorGcCount":0,"maxLiveBytes":1,"maxMemInUseBytes":1,"mutatorCpuNs":1,"gcCpuNs":1}',
      '[diagnostic-runtime] {"allocatedBytes":2,"copiedBytes":2,"gcCount":2,"majorGcCount":0,"maxLiveBytes":2,"maxMemInUseBytes":2,"mutatorCpuNs":2,"gcCpuNs":2}',
    ].join('\n'));
    fs.writeFileSync(path.join(outputDir, 'runtime-resources.tsv'), '1\t1\t1\t0\t1\t0\n2\t1\t2\t0\t1\t0\n');
    fs.writeFileSync(path.join(outputDir, 'runtime-resources.json'), '{"sampleCount":2,"cpuSeconds":1,"peakRssKiB":1,"elapsedSeconds":1}\n');
    fs.writeFileSync(path.join(outputDir, 'live-profile.json'), JSON.stringify({ summary: {
      rates: { invalidationCount: 10_000_000 },
      counters: { profile_live_subscribed: 1, profile_live_fragments: 10_000_000 },
      serverInvalidation: { labels: Array.from({ length: 100 }, (_, index) => ({ label: `bounded-${index}`, count: 100_000, avgTotalMs: 2, p95TotalMs: 3 })) },
    } }));

    const result = spawnSync(process.execPath, ['e2e/diagnostic-profile-report.mjs', outputDir, '4'], { cwd: repoRoot, encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    const report = JSON.parse(fs.readFileSync(path.join(outputDir, 'diagnostic-profile.json'), 'utf8'));
    assert.equal(report.database.queries.fingerprintCount, 256);
    assert.equal(report.database.queries.fingerprintsTruncated, true);
    assert.equal(report.database.queries.slowFingerprints.length, 20);
    assert.equal(report.pressure.categories.find((row) => row.category === 'live_update').sampleCount, 10_000_000);
    assert.equal(report.liveUpdate.fragments, 10_000_000);
    assert.equal(report.liveUpdate.fanoutDeliveries, 10_000_000);
    assert.equal(report.liveUpdate.labelCount, 100);
    assert.equal(report.liveUpdate.labelsTruncated, true);
    assert.equal(report.liveUpdate.labels.length, 64);
    assert.equal(report.liveUpdate.labels.find((row) => row.label === 'other').p95TotalMs, 3);
  } finally {
    fs.rmSync(outputDir, { recursive: true, force: true });
  }
});

test('diagnostic profile writes evidence then fails missing coverage budgets', () => {
  const outputDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bepis-diagnostic-profile-budget-'));
  try {
    fs.writeFileSync(path.join(outputDir, 'server.log'), '');
    const result = spawnSync(process.execPath, ['e2e/diagnostic-profile-report.mjs', outputDir, '4'], { cwd: repoRoot, encoding: 'utf8' });
    assert.equal(result.status, 2, result.stderr);
    const report = JSON.parse(fs.readFileSync(path.join(outputDir, 'diagnostic-profile.json'), 'utf8'));
    assert.equal(report.regressionBudget.passed, false);
    assert.ok(report.regressionBudget.checks.some((check) => check.name === 'process runtime sample coverage' && !check.passed));
    assert.ok(report.regressionBudget.checks.some((check) => check.name === 'pool sample coverage' && !check.passed));
  } finally {
    fs.rmSync(outputDir, { recursive: true, force: true });
  }
});

test('load profile reporter exits nonzero when correctness budget fails', () => {
  const outputDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bepis-load-profile-budget-'));
  try {
    const metricsPath = path.join(outputDir, 'metrics.ndjson');
    fs.writeFileSync(metricsPath, [
      { type: 'Point', metric: 'http_req_duration', data: { value: 10, time: '2026-01-01T00:00:00Z', tags: { scenario: 'staff', route: 'staff.profile', status: '500' } } },
      { type: 'Point', metric: 'iterations', data: { value: 1, time: '2026-01-01T00:00:01Z', tags: {} } },
      { type: 'Point', metric: 'checks', data: { value: 1, time: '2026-01-01T00:00:01Z', tags: { check: 'status' } } },
    ].map((row) => JSON.stringify(row)).join('\n'));
    const result = spawnSync(process.execPath, ['e2e/profile-load-report.mjs', metricsPath, outputDir], { cwd: repoRoot, encoding: 'utf8' });
    assert.equal(result.status, 2, result.stderr);
    const profile = JSON.parse(fs.readFileSync(path.join(outputDir, 'load-profile.json'), 'utf8'));
    assert.equal(profile.summary.regressionBudget.passed, false);
  } finally {
    fs.rmSync(outputDir, { recursive: true, force: true });
  }
});

test('diagnostic profile aggregates bounded privacy-safe evidence', () => {
  const outputDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bepis-diagnostic-profile-'));
  try {
    fs.writeFileSync(path.join(outputDir, 'server.log'), [
      '🔍 SELECT users.email FROM users WHERE users.id = $1 (12ms)',
      '🔍 SELECT users.email FROM users WHERE users.id = $1 (8ms)',
      '[diagnostic-runtime] {"allocatedBytes":100,"copiedBytes":20,"gcCount":1,"majorGcCount":0,"maxLiveBytes":50,"maxMemInUseBytes":100,"mutatorCpuNs":100000000,"gcCpuNs":10000000}',
      '[diagnostic-runtime] {"allocatedBytes":1100,"copiedBytes":120,"gcCount":3,"majorGcCount":1,"maxLiveBytes":500,"maxMemInUseBytes":1000,"mutatorCpuNs":600000000,"gcCpuNs":60000000}',
    ].join('\n'));
    fs.writeFileSync(path.join(outputDir, 'runtime-resources.tsv'), '1\t100\t10\t2\t3\t0\n2\t200\t20\t4\t5\t1\n');
    fs.writeFileSync(path.join(outputDir, 'runtime-resources.json'), '{"sampleCount":2,"cpuSeconds":1.5,"peakRssKiB":200,"elapsedSeconds":2}\n');
    fs.writeFileSync(path.join(outputDir, 'otel-traces.json'), '{"resourceSpans":[{"scopeSpans":[{"spans":[{"name":"render.respond_html","startTimeUnixNano":"1000000","endTimeUnixNano":"3000000","attributes":[]}]}]}]}\n');

    const result = spawnSync(process.execPath, ['e2e/diagnostic-profile-report.mjs', outputDir, '4'], {
      cwd: repoRoot,
      encoding: 'utf8',
    });
    assert.equal(result.status, 0, result.stderr);
    const rawReport = fs.readFileSync(path.join(outputDir, 'diagnostic-profile.json'), 'utf8');
    const report = JSON.parse(rawReport);

    assert.equal(report.database.queries.sampleCount, 2);
    assert.equal(report.database.queries.totalDurationMs, 20);
    assert.equal(report.database.queries.slowFingerprints.length, 1);
    assert.match(report.database.queries.slowFingerprints[0].fingerprint, /^[a-f0-9]{16}$/);
    assert.equal(report.database.connectionPool.waitEvidence, 'possible_saturation');
    assert.equal(report.runtime.ghc.allocatedBytes, 1000);
    assert.equal(report.pressure.categories.find((row) => row.category === 'render').sampleCount, 1);
    assert.equal(report.regressionBudget.passed, true);
    assert.equal(report.privacy.queryTextIncluded, false);
    assert.doesNotMatch(rawReport, /users\.email|users\.id|SELECT users/i);
  } finally {
    fs.rmSync(outputDir, { recursive: true, force: true });
  }
});
