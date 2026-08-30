#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const percentileSampleCapacity = 4096;
const fingerprintCapacity = 256;
const fingerprintPercentileSampleCapacity = 128;
const liveLabelCapacity = 64;

if (process.argv.length < 4) {
  console.error('Usage: node e2e/diagnostic-profile-report.mjs <profile-output-dir> <pool-size>');
  process.exit(64);
}

const outputDir = path.resolve(process.argv[2]);
const poolSize = positiveInt(process.argv[3], 20);
const budgetCatalog = JSON.parse(fs.readFileSync(path.resolve(process.env.PROFILE_BUDGET_CATALOG || 'e2e/profile-regression-budgets.json'), 'utf8'));
const serverLog = readIfExists(path.join(outputDir, 'server.log'));
const queryEvidence = summarizeQueries(serverLog);
const poolEvidence = summarizePoolSamples(path.join(outputDir, 'runtime-resources.tsv'), poolSize, serverLog);
const runtimeEvidence = summarizeRuntime(serverLog, path.join(outputDir, 'runtime-resources.json'));
const liveEvidence = summarizeLive(path.join(outputDir, 'live-profile.json'));
const pressure = summarizePressure(path.join(outputDir, 'otel-traces.json'), queryEvidence, runtimeEvidence, liveEvidence);
const budget = evaluateBudget(budgetCatalog.diagnostic || {}, queryEvidence, poolEvidence, runtimeEvidence, liveEvidence);
const report = {
  schemaVersion: 1,
  collection: 'diagnostic-only',
  sampleCounts: {
    queries: queryEvidence.sampleCount,
    pool: poolEvidence.sampleCount,
    ghcRuntime: runtimeEvidence.ghc.sampleCount,
    processRuntime: runtimeEvidence.process.sampleCount,
    spans: pressure.spanCount,
    liveUpdate: liveEvidence.sampleCount,
  },
  pressure,
  database: { queries: queryEvidence, connectionPool: poolEvidence },
  runtime: runtimeEvidence,
  liveUpdate: liveEvidence,
  regressionBudget: budget,
  privacy: {
    queryTextIncluded: false,
    queryParametersIncluded: false,
    customerIdentifiersIncluded: false,
    fingerprintAlgorithm: 'sha256(normalized-parameterized-statement), first 16 hex characters',
  },
};

fs.writeFileSync(path.join(outputDir, 'diagnostic-profile.json'), `${JSON.stringify(report, null, 2)}\n`);
fs.writeFileSync(path.join(outputDir, 'diagnostic-profile.md'), renderMarkdown(report));
console.log(`Diagnostic profile: ${path.join(outputDir, 'diagnostic-profile.md')}`);
if (!report.regressionBudget.passed) process.exitCode = 2;

function positiveInt(value, fallback) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function readIfExists(filePath) {
  return fs.existsSync(filePath) ? fs.readFileSync(filePath, 'utf8') : '';
}

function round(value) { return Math.round(value * 10) / 10; }
function percentile(values, ratio) {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * ratio) - 1)];
}
function weightedPercentile(samples, ratio) {
  if (!samples.length) return 0;
  const sorted = [...samples].sort((a, b) => a.value - b.value);
  const totalWeight = sorted.reduce((sum, sample) => sum + sample.weight, 0);
  const target = totalWeight * ratio;
  let observed = 0;
  for (const sample of sorted) {
    observed += sample.weight;
    if (observed >= target) return sample.value;
  }
  return sorted.at(-1).value;
}
function formatBytes(value) {
  if (!Number.isFinite(value)) return '0 B';
  if (value >= 1024 * 1024) return `${round(value / (1024 * 1024))} MiB`;
  if (value >= 1024) return `${round(value / 1024)} KiB`;
  return `${round(value)} B`;
}

function appendBoundedSample(samples, value, seenCount, capacity) {
  if (samples.length < capacity) samples.push(value);
  else samples[(seenCount - 1) % capacity] = value;
}

function summarizeQueries(content) {
  const groups = new Map();
  let sampleCount = 0;
  let totalDurationMs = 0;
  let maxDurationMs = 0;
  let fingerprintsTruncated = false;
  const durationSamples = [];
  for (const line of content.split('\n')) {
    const match = line.match(/[🔍💾]\s+(.+)\s+\((\d+)ms\)\s*$/u);
    if (!match) continue;
    const normalized = normalizeStatement(match[1]);
    const durationMs = Number(match[2]);
    const fingerprint = crypto.createHash('sha256').update(normalized).digest('hex').slice(0, 16);
    const operation = (/^[a-z]+/.exec(normalized)?.[0] || 'other').toUpperCase();
    let group = groups.get(fingerprint);
    if (!group && groups.size < fingerprintCapacity) {
      group = { fingerprint, operation, sampleCount: 0, totalDurationMs: 0, maxDurationMs: 0, durationSamples: [] };
      groups.set(fingerprint, group);
    } else if (!group) {
      fingerprintsTruncated = true;
      const leastSlow = [...groups.values()].sort((a, b) => a.totalDurationMs - b.totalDurationMs)[0];
      if (durationMs > leastSlow.totalDurationMs) {
        groups.delete(leastSlow.fingerprint);
        group = { fingerprint, operation, sampleCount: 0, totalDurationMs: 0, maxDurationMs: 0, durationSamples: [] };
        groups.set(fingerprint, group);
      }
    }
    if (group) {
      group.sampleCount += 1;
      group.totalDurationMs += durationMs;
      group.maxDurationMs = Math.max(group.maxDurationMs, durationMs);
      appendBoundedSample(group.durationSamples, durationMs, group.sampleCount, fingerprintPercentileSampleCapacity);
    }
    sampleCount += 1;
    totalDurationMs += durationMs;
    maxDurationMs = Math.max(maxDurationMs, durationMs);
    appendBoundedSample(durationSamples, durationMs, sampleCount, percentileSampleCapacity);
  }
  const slowFingerprints = [...groups.values()].map((group) => ({
    fingerprint: group.fingerprint,
    operation: group.operation,
    sampleCount: group.sampleCount,
    totalDurationMs: group.totalDurationMs,
    p95DurationMs: percentile(group.durationSamples, 0.95),
    maxDurationMs: group.maxDurationMs,
  })).sort((a, b) => b.totalDurationMs - a.totalDurationMs || b.maxDurationMs - a.maxDurationMs).slice(0, 20);
  return {
    sampleCount,
    totalDurationMs,
    p95DurationMs: percentile(durationSamples, 0.95),
    maxDurationMs,
    fingerprintCount: groups.size,
    fingerprintCapacity,
    fingerprintsTruncated,
    percentileSampleCount: durationSamples.length,
    slowFingerprints,
  };
}

function normalizeStatement(statement) {
  return statement
    .replace(/^runSessionHasql$/i, 'session')
    .replace(/'(?:''|[^'])*'/g, '?')
    .replace(/\$\d+/g, '?')
    .replace(/\b\d+(?:\.\d+)?\b/g, '?')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

function summarizePoolSamples(filePath, capacity, serverLog) {
  const samples = readIfExists(filePath).split('\n').filter(Boolean).map((line) => {
    const fields = line.split('\t').map(Number);
    return { active: fields[3] || 0, total: fields[4] || 0, serverWaiters: fields[5] || 0 };
  });
  const saturatedSampleCount = samples.filter((sample) => sample.active >= capacity).length;
  const acquisitionTimeoutCount = (serverLog.match(/AcquisitionTimeoutUsageError/g) || []).length;
  return {
    sampleCount: samples.length,
    capacity,
    maxActiveConnections: Math.max(0, ...samples.map((sample) => sample.active)),
    maxOpenConnections: Math.max(0, ...samples.map((sample) => sample.total)),
    serverWaitSampleCount: samples.filter((sample) => sample.serverWaiters > 0).length,
    saturatedSampleCount,
    acquisitionTimeoutCount,
    waitEvidence: acquisitionTimeoutCount > 0 ? 'observed_timeout' : saturatedSampleCount > 0 ? 'possible_saturation' : 'not_observed',
    limitation: 'Hasql does not expose acquisition wait duration; saturation samples and acquisition timeouts are bounded run-level proxies.',
  };
}

function summarizeRuntime(serverLog, resourcePath) {
  const rangeKeys = ['allocatedBytes', 'copiedBytes', 'gcCount', 'majorGcCount', 'mutatorCpuNs', 'gcCpuNs'];
  const ranges = Object.fromEntries(rangeKeys.map((key) => [key, { min: Infinity, max: 0 }]));
  let sampleCount = 0;
  let maxLiveBytes = 0;
  let maxMemInUseBytes = 0;
  for (const line of serverLog.split('\n')) {
    const marker = '[diagnostic-runtime] ';
    const index = line.indexOf(marker);
    if (index === -1) continue;
    try {
      const sample = JSON.parse(line.slice(index + marker.length));
      sampleCount += 1;
      for (const key of rangeKeys) {
        const value = Number(sample[key] || 0);
        if (!Number.isFinite(value)) continue;
        ranges[key].min = Math.min(ranges[key].min, value);
        ranges[key].max = Math.max(ranges[key].max, value);
      }
      maxLiveBytes = Math.max(maxLiveBytes, Number(sample.maxLiveBytes || 0));
      maxMemInUseBytes = Math.max(maxMemInUseBytes, Number(sample.maxMemInUseBytes || 0));
    } catch { /* incomplete concurrent log line */ }
  }
  const sampledRange = (key) => sampleCount > 0 ? Math.max(0, ranges[key].max - ranges[key].min) : 0;
  const process = fs.existsSync(resourcePath) ? JSON.parse(fs.readFileSync(resourcePath, 'utf8')) : {};
  return {
    ghc: {
      sampleCount,
      allocatedBytes: sampledRange('allocatedBytes'),
      copiedBytes: sampledRange('copiedBytes'),
      gcCount: sampledRange('gcCount'),
      majorGcCount: sampledRange('majorGcCount'),
      mutatorCpuSeconds: round(sampledRange('mutatorCpuNs') / 1e9),
      gcCpuSeconds: round(sampledRange('gcCpuNs') / 1e9),
      maxLiveBytes,
      maxMemInUseBytes,
    },
    process: {
      sampleCount: Number(process.sampleCount || 0),
      cpuSeconds: Number(process.cpuSeconds || 0),
      peakRssKiB: Number(process.peakRssKiB || 0),
      elapsedSeconds: Number(process.elapsedSeconds || 0),
    },
  };
}

function evaluateBudget(config, queries, pool, runtime, live) {
  const checks = [
    { name: 'query sample coverage', actual: queries.sampleCount, operator: '>=', limit: config.minimumQuerySamples ?? 1, passed: queries.sampleCount >= (config.minimumQuerySamples ?? 1) },
    { name: 'GHC runtime sample coverage', actual: runtime.ghc.sampleCount, operator: '>=', limit: config.minimumGhcRuntimeSamples ?? 2, passed: runtime.ghc.sampleCount >= (config.minimumGhcRuntimeSamples ?? 2) },
    { name: 'process runtime sample coverage', actual: runtime.process.sampleCount, operator: '>=', limit: config.minimumProcessRuntimeSamples ?? 1, passed: runtime.process.sampleCount >= (config.minimumProcessRuntimeSamples ?? 1) },
    { name: 'profile process observed', actual: runtime.process.peakRssKiB, operator: '>', limit: 0, passed: runtime.process.peakRssKiB > 0 },
    { name: 'pool sample coverage', actual: pool.sampleCount, operator: '>=', limit: config.minimumPoolSamples ?? 1, passed: pool.sampleCount >= (config.minimumPoolSamples ?? 1) },
    { name: 'pool acquisition timeouts', actual: pool.acquisitionTimeoutCount, operator: '<=', limit: config.maximumPoolAcquisitionTimeouts ?? 0, passed: pool.acquisitionTimeoutCount <= (config.maximumPoolAcquisitionTimeouts ?? 0) },
  ];
  if (live.sampleCount > 0) checks.push({ name: 'live drops/errors', actual: live.dropped, operator: '<=', limit: config.maximumLiveDropsOrErrors ?? 0, passed: live.dropped <= (config.maximumLiveDropsOrErrors ?? 0) });
  return { passed: checks.every((check) => check.passed), checks, latencyBudget: 'matched-baseline-required' };
}

function summarizeLive(filePath) {
  if (!fs.existsSync(filePath)) return { sampleCount: 0, subscribers: 0, invalidations: 0, fanoutDeliveries: 0, fragments: 0, dropped: 0, labelCount: 0, labelsTruncated: false, labels: [] };
  const profile = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const summary = profile.summary || {};
  const labels = [];
  let labelCount = 0;
  const overflow = { count: 0, totalMs: 0, fragments: 0, subscribers: 0, maxTotalMs: 0, maxSubscribers: 0, p95Samples: [] };
  const addOverflow = (row) => {
    overflow.count += row.count;
    overflow.totalMs += row.avgTotalMs * row.count;
    overflow.fragments += row.avgFragments * row.count;
    overflow.subscribers += row.avgSubscribers * row.count;
    overflow.maxTotalMs = Math.max(overflow.maxTotalMs, row.maxTotalMs);
    overflow.maxSubscribers = Math.max(overflow.maxSubscribers, row.maxSubscribers);
    const sample = { value: row.p95TotalMs, weight: row.count };
    if (overflow.p95Samples.length < liveLabelCapacity) overflow.p95Samples.push(sample);
    else overflow.p95Samples[(labelCount - 1) % liveLabelCapacity] = sample;
  };
  for (const rawRow of summary.serverInvalidation?.labels || []) {
    labelCount += 1;
    const row = {
      label: String(rawRow.label || 'unknown').replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 80),
      count: Number(rawRow.count || 0),
      avgTotalMs: Number(rawRow.avgTotalMs || 0),
      p95TotalMs: Number(rawRow.p95TotalMs || 0),
      maxTotalMs: Number(rawRow.maxTotalMs || 0),
      avgFragments: Number(rawRow.avgFragments || 0),
      avgSubscribers: Number(rawRow.avgSubscribers || 0),
      maxSubscribers: Number(rawRow.maxSubscribers || 0),
    };
    if (labels.length < liveLabelCapacity - 1) {
      labels.push(row);
    } else {
      const leastIndex = labels.reduce((selected, candidate, index) => candidate.count < labels[selected].count ? index : selected, 0);
      if (row.count > labels[leastIndex].count) {
        addOverflow(labels[leastIndex]);
        labels[leastIndex] = row;
      } else addOverflow(row);
    }
  }
  labels.sort((a, b) => b.count - a.count || a.label.localeCompare(b.label));
  if (overflow.count > 0) {
    labels.push({
      label: 'other', count: overflow.count, avgTotalMs: overflow.totalMs / overflow.count,
      p95TotalMs: weightedPercentile(overflow.p95Samples, 0.95),
      maxTotalMs: overflow.maxTotalMs, avgFragments: overflow.fragments / overflow.count,
      avgSubscribers: overflow.subscribers / overflow.count, maxSubscribers: overflow.maxSubscribers,
    });
  }
  return {
    sampleCount: Number(summary.rates?.invalidationCount || 0),
    subscribers: Number(summary.counters?.profile_live_subscribed || 0),
    invalidations: Number(summary.rates?.invalidationCount || 0),
    fanoutDeliveries: Number(summary.rates?.invalidationCount || 0),
    fragments: Number(summary.counters?.profile_live_fragments || 0),
    dropped: Number(summary.counters?.profile_live_missed_own_invalidations || 0) + Number(summary.counters?.profile_live_errors || 0),
    labelCount,
    labelsTruncated: overflow.count > 0,
    labels,
  };
}

function summarizePressure(tracePath, queryEvidence, runtimeEvidence, liveEvidence) {
  const groups = new Map(['db', 'runtime', 'render', 'external', 'live_update', 'other'].map((name) => [name, { sampleCount: 0, totalDurationMs: 0, maxDurationMs: 0, samples: [] }]));
  const addSample = (category, durationMs, weight = 1) => {
    const group = groups.get(category);
    group.sampleCount += weight;
    group.totalDurationMs += durationMs * weight;
    group.maxDurationMs = Math.max(group.maxDurationMs, durationMs);
    const sample = { value: durationMs, weight };
    if (group.samples.length < percentileSampleCapacity) group.samples.push(sample);
    else group.samples[(group.sampleCount - 1) % percentileSampleCapacity] = sample;
  };
  let spanCount = 0;
  if (fs.existsSync(tracePath)) {
    const documents = parseJsonDocuments(fs.readFileSync(tracePath, 'utf8'));
    walk(documents, (value) => {
      if (!value || typeof value !== 'object' || !value.name || !value.startTimeUnixNano || !value.endTimeUnixNano) return;
      const durationMs = Number(BigInt(value.endTimeUnixNano) - BigInt(value.startTimeUnixNano)) / 1e6;
      addSample(pressureCategory(value.name, value.attributes || []), durationMs);
      spanCount += 1;
    });
  }
  if (runtimeEvidence.process.elapsedSeconds > 0) addSample('runtime', runtimeEvidence.process.cpuSeconds * 1000);
  for (const row of liveEvidence.labels) addSample('live_update', Number(row.avgTotalMs || 0), Number(row.count || 0));
  const categories = [...groups.entries()].map(([category, group]) => ({
    category,
    sampleCount: group.sampleCount,
    totalDurationMs: round(group.totalDurationMs),
    p95DurationMs: round(weightedPercentile(group.samples, 0.95)),
    maxDurationMs: round(group.maxDurationMs),
  }));
  const database = categories.find((row) => row.category === 'db');
  database.sampleCount += queryEvidence.sampleCount;
  database.totalDurationMs = round(database.totalDurationMs + queryEvidence.totalDurationMs);
  database.p95DurationMs = Math.max(database.p95DurationMs, queryEvidence.p95DurationMs);
  database.maxDurationMs = Math.max(database.maxDurationMs, queryEvidence.maxDurationMs);
  return { spanCount, categories };
}

function pressureCategory(name, attributes) {
  const keys = new Set(attributes.map((attribute) => attribute.key));
  if (keys.has('db.system') || /(^|[._])(db|sql|query)([._]|$)/i.test(name)) return 'db';
  if (/render|html/i.test(name)) return 'render';
  if (/provider|external|stripe|xero|fwc|email/i.test(name)) return 'external';
  if (/live[._-]?update|invalidate|websocket/i.test(name)) return 'live_update';
  if (/runtime|gc|heap/i.test(name)) return 'runtime';
  return 'other';
}

function parseJsonDocuments(content) {
  const trimmed = content.trim();
  if (!trimmed) return [];
  try { const parsed = JSON.parse(trimmed); return Array.isArray(parsed) ? parsed : [parsed]; }
  catch { return trimmed.split('\n').filter(Boolean).map((line) => JSON.parse(line)); }
}
function walk(value, visit) {
  if (Array.isArray(value)) return value.forEach((item) => walk(item, visit));
  if (!value || typeof value !== 'object') return;
  visit(value);
  Object.values(value).forEach((item) => walk(item, visit));
}

function renderMarkdown(report) {
  const q = report.database.queries;
  const p = report.database.connectionPool;
  const g = report.runtime.ghc;
  const r = report.runtime.process;
  return `# Diagnostic Profile\n\nCollection: diagnostic/profile gate only. Query and customer data omitted.\n\nBudget: **${report.regressionBudget.passed ? 'pass' : 'insufficient/fail'}**; latency budget requires a matched baseline.\n\n## Sample Counts\n\n- Queries: ${q.sampleCount}\n- Pool samples: ${p.sampleCount}\n- GHC runtime samples: ${g.sampleCount}\n- Process samples: ${r.sampleCount}\n- OpenTelemetry spans: ${report.pressure.spanCount}\n\n## Pressure Categories\n\n| Category | Samples | Total ms | P95 ms | Max ms |\n| --- | ---: | ---: | ---: | ---: |\n${report.pressure.categories.map((row) => `| ${row.category} | ${row.sampleCount} | ${row.totalDurationMs} | ${row.p95DurationMs} | ${row.maxDurationMs} |`).join('\n')}\n\n## Database\n\nQueries: ${q.sampleCount}; aggregate duration: ${q.totalDurationMs}ms; safe fingerprints: ${q.fingerprintCount}.\n\n| Fingerprint | Operation | Samples | Total ms | P95 ms | Max ms |\n| --- | --- | ---: | ---: | ---: | ---: |\n${q.slowFingerprints.map((row) => `| \`${row.fingerprint}\` | ${row.operation} | ${row.sampleCount} | ${row.totalDurationMs} | ${row.p95DurationMs} | ${row.maxDurationMs} |`).join('\n')}\n\n## Connection Pool\n\nCapacity: ${p.capacity}; max active: ${p.maxActiveConnections}; max open: ${p.maxOpenConnections}; saturated samples: ${p.saturatedSampleCount}/${p.sampleCount}; acquisition timeouts: ${p.acquisitionTimeoutCount}; wait evidence: \`${p.waitEvidence}\`.\n\n${p.limitation}\n\n## Runtime\n\nAllocated: ${formatBytes(g.allocatedBytes)}; copied by GC: ${formatBytes(g.copiedBytes)}; collections: ${g.gcCount} (${g.majorGcCount} major); peak live heap: ${formatBytes(g.maxLiveBytes)}; GHC max memory: ${formatBytes(g.maxMemInUseBytes)}; mutator CPU: ${g.mutatorCpuSeconds}s; GC CPU: ${g.gcCpuSeconds}s.\n\nProcess CPU: ${r.cpuSeconds}s; peak RSS: ${formatBytes(r.peakRssKiB * 1024)} over ${r.elapsedSeconds}s.\n\n## Live Update\n\nSubscribers: ${report.liveUpdate.subscribers}; fanout deliveries: ${report.liveUpdate.fanoutDeliveries}; invalidations: ${report.liveUpdate.invalidations}; fragments: ${report.liveUpdate.fragments}; dropped/errors: ${report.liveUpdate.dropped}; aggregate samples: ${report.liveUpdate.sampleCount}.\n`;
}
