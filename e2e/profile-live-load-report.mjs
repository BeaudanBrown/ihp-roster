#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const failureMetricNames = new Set([
    'profile_live_errors',
    'profile_live_failed_mutations',
    'profile_live_missed_own_invalidations',
]);

if (process.argv.length < 4) {
    console.log('Usage: node e2e/profile-live-load-report.mjs <k6-metrics.ndjson> <output-dir> [metadata.json]');
    process.exit(64);
}

const metricsPath = path.resolve(process.argv[2]);
const outputDir = path.resolve(process.argv[3]);
const metadataPath = process.argv[4] ? path.resolve(process.argv[4]) : null;
const metadata = metadataPath && fs.existsSync(metadataPath) ? JSON.parse(fs.readFileSync(metadataPath, 'utf8')) : {};
const serverLogPath = path.join(outputDir, 'server.log');
const summary = summarize(metricsPath, serverLogPath);
fs.mkdirSync(outputDir, { recursive: true });
fs.writeFileSync(path.join(outputDir, 'live-profile.json'), JSON.stringify({ metadata, summary }, null, 2));
fs.writeFileSync(path.join(outputDir, 'live-profile.md'), renderMarkdown(metadata, summary));
console.log(`Live profile summary: ${path.join(outputDir, 'live-profile.md')}`);

function summarize(filePath, logPath) {
    const counters = new Map();
    const trends = new Map();
    const taggedCounters = new Map();
    const taggedTrends = new Map();
    const checks = { total: 0, failed: 0, byName: new Map() };
    const httpStatuses = new Map();
    const points = [];
    const mutations = [];
    const invalidations = [];
    const ownInvalidations = [];

    const content = fs.readFileSync(filePath, 'utf8');
    for (const line of content.split('\n')) {
        if (!line.trim()) continue;
        const event = JSON.parse(line);
        if (event.type !== 'Point') continue;
        const data = event.data || {};
        const tags = data.tags || {};
        const value = Number(data.value);
        const time = Date.parse(data.time);
        if (!Number.isFinite(value)) continue;
        if (Number.isFinite(time)) points.push({ metric: event.metric, value, time, tags });

        if (event.metric === 'checks') {
            checks.total += 1;
            if (value === 0) checks.failed += 1;
            const name = tags.check || 'unknown';
            const current = checks.byName.get(name) || { total: 0, failed: 0 };
            current.total += 1;
            if (value === 0) current.failed += 1;
            checks.byName.set(name, current);
        } else if (event.metric.startsWith('profile_live_')) {
            if (event.metric.endsWith('_duration') || event.metric.endsWith('_latency')) {
                addTrend(trends, event.metric, value);
                addTaggedTrend(taggedTrends, event.metric, tags, value);
            } else {
                counters.set(event.metric, (counters.get(event.metric) || 0) + value);
                addTaggedCounter(taggedCounters, event.metric, tags, value);
                if (event.metric === 'profile_live_invalidations' && Number.isFinite(time)) invalidations.push({ value, time, tags });
                if (event.metric === 'profile_live_own_invalidations' && Number.isFinite(time)) ownInvalidations.push({ value, time, tags });
            }
        } else if (event.metric === 'http_req_duration') {
            const route = tags.route || 'unknown';
            const status = String(tags.status || 'unknown');
            const key = `${route}:${status}`;
            httpStatuses.set(key, (httpStatuses.get(key) || 0) + 1);
            if (route.startsWith('live.') && route.endsWith('_mutation')) {
                mutations.push({ value, time, tags });
            }
        }
    }

    return {
        rates: rateSummary(points, mutations, invalidations, ownInvalidations),
        counters: Object.fromEntries([...counters.entries()].sort()),
        trends: Object.fromEntries([...trends.entries()].sort().map(([name, values]) => [name, trendSummary(values)])),
        taggedCounters: [...taggedCounters.entries()].sort().map(([key, value]) => ({ ...JSON.parse(key), count: value })),
        taggedTrends: [...taggedTrends.entries()].sort().map(([key, values]) => ({ ...JSON.parse(key), ...trendSummary(values) })),
        failureSummary: summarizeFailures(taggedCounters, checks.byName),
        mutationsBySurface: summarizeMutationSurfaces(mutations),
        checks: {
            total: checks.total,
            failed: checks.failed,
            byName: Object.fromEntries([...checks.byName.entries()].sort()),
        },
        httpStatuses: Object.fromEntries([...httpStatuses.entries()].sort()),
        serverInvalidation: summarizeServerInvalidations(logPath),
    };
}

function rateSummary(points, mutations, invalidations, ownInvalidations) {
    const runWindow = pointWindow(points);
    const mutationWindow = pointWindow(mutations);
    const invalidationWindow = weightedWindow(invalidations);
    const ownWindow = weightedWindow(ownInvalidations);
    const mutationCount = mutations.length;
    const invalidationCount = sumValues(invalidations);
    const ownCount = sumValues(ownInvalidations);
    return {
        runDurationSec: round(runWindow.durationSec),
        mutationCount,
        mutationRatePerSec: rate(mutationCount, runWindow.durationSec),
        mutationBurstWindowSec: round(mutationWindow.durationSec),
        mutationBurstRatePerSec: rate(mutationCount, mutationWindow.durationSec),
        invalidationCount,
        invalidationRatePerSec: rate(invalidationCount, runWindow.durationSec),
        invalidationDeliveryWindowSec: round(invalidationWindow.durationSec),
        invalidationDeliveryRatePerSec: rate(invalidationCount, invalidationWindow.durationSec),
        ownInvalidationCount: ownCount,
        ownInvalidationRatePerSec: rate(ownCount, runWindow.durationSec),
        ownInvalidationBurstWindowSec: round(ownWindow.durationSec),
        ownInvalidationBurstRatePerSec: rate(ownCount, ownWindow.durationSec),
    };
}

function pointWindow(points) {
    const times = points.map((point) => point.time).filter(Number.isFinite);
    if (times.length === 0) return { durationSec: 0 };
    return { durationSec: Math.max(0, (Math.max(...times) - Math.min(...times)) / 1000) };
}

function weightedWindow(points) {
    return pointWindow(points.filter((point) => point.value > 0));
}

function sumValues(points) {
    return points.reduce((sum, point) => sum + point.value, 0);
}

function rate(count, seconds) {
    return seconds > 0 ? round(count / seconds) : count;
}

function summarizeMutationSurfaces(points) {
    const grouped = groupBy(points, (point) => point.tags.surface || 'unknown');
    return [...grouped.entries()].sort().map(([surface, rows]) => {
        const values = rows.map((row) => row.value);
        return {
            surface,
            count: rows.length,
            medianMs: round(percentile(values, 0.5)),
            p95Ms: round(percentile(values, 0.95)),
            p99Ms: round(percentile(values, 0.99)),
            maxMs: round(Math.max(...values)),
        };
    });
}

function summarizeServerInvalidations(logPath) {
    if (!fs.existsSync(logPath)) return { labels: [], slowestLabels: [] };
    const labels = new Map();
    const content = fs.readFileSync(logPath, 'utf8');
    for (const line of content.split('\n')) {
        const marker = '[live-invalidation] ';
        const index = line.indexOf(marker);
        if (index === -1) continue;
        const fields = parseKeyValues(line.slice(index + marker.length));
        const label = fields.label || 'unknown';
        if (!/^[A-Za-z0-9._-]+$/.test(label) || fields.total_ms === undefined) continue;
        const current = labels.get(label) || {
            label,
            count: 0,
            totalMs: [],
            observeMs: [],
            activeMs: [],
            expandMs: [],
            candidateMs: [],
            planMs: [],
            broadcastMs: [],
            touched: [],
            activeScopes: [],
            expanded: [],
            candidateScopes: [],
            planningScopes: [],
            targets: [],
            targetFragments: [],
            broadcasts: [],
            subscribers: [],
        };
        current.count += 1;
        pushNumber(current.totalMs, fields.total_ms);
        pushNumber(current.observeMs, fields.observe_ms);
        pushNumber(current.activeMs, fields.active_ms);
        pushNumber(current.expandMs, fields.expand_ms);
        pushNumber(current.candidateMs, fields.candidate_ms);
        pushNumber(current.planMs, fields.plan_ms);
        pushNumber(current.broadcastMs, fields.broadcast_ms);
        pushNumber(current.touched, fields.touched);
        pushNumber(current.activeScopes, fields.active_scopes);
        pushNumber(current.expanded, fields.expanded);
        pushNumber(current.candidateScopes, fields.candidate_scopes);
        pushNumber(current.planningScopes, fields.planning_scopes);
        pushNumber(current.targets, fields.targets);
        pushNumber(current.targetFragments, fields.target_fragments);
        pushNumber(current.broadcasts, fields.broadcasts);
        pushNumber(current.subscribers, fields.subscribers);
        labels.set(label, current);
    }

    const rows = [...labels.values()].map((row) => ({
        label: row.label,
        count: row.count,
        avgTotalMs: round(avg(row.totalMs)),
        p95TotalMs: round(percentile(row.totalMs, 0.95)),
        maxTotalMs: round(max(row.totalMs)),
        avgPlanMs: round(avg(row.planMs)),
        avgBroadcastMs: round(avg(row.broadcastMs)),
        avgActiveScopes: round(avg(row.activeScopes)),
        avgExpanded: round(avg(row.expanded)),
        avgTargets: round(avg(row.targets)),
        avgFragments: round(avg(row.targetFragments)),
        avgSubscribers: round(avg(row.subscribers)),
        maxSubscribers: round(max(row.subscribers)),
    })).sort((a, b) => a.label.localeCompare(b.label));

    return {
        labels: rows,
        slowestLabels: [...rows].sort((a, b) => b.p95TotalMs - a.p95TotalMs || b.maxTotalMs - a.maxTotalMs).slice(0, 5),
        highestFanoutLabels: [...rows].sort((a, b) => b.maxSubscribers - a.maxSubscribers || b.avgFragments - a.avgFragments).slice(0, 5),
    };
}

function parseKeyValues(text) {
    const fields = {};
    for (const part of text.trim().split(/\s+/)) {
        const index = part.indexOf('=');
        if (index === -1) continue;
        fields[part.slice(0, index)] = part.slice(index + 1);
    }
    return fields;
}

function pushNumber(values, value) {
    const number = Number(value);
    if (Number.isFinite(number)) values.push(number);
}

function addTrend(map, metric, value) {
    if (!map.has(metric)) map.set(metric, []);
    map.get(metric).push(value);
}

function addTaggedCounter(map, metric, tags, value) {
    const key = tagKey(metric, tags);
    map.set(key, (map.get(key) || 0) + value);
}

function addTaggedTrend(map, metric, tags, value) {
    const key = tagKey(metric, tags);
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(value);
}

function tagKey(metric, tags) {
    return JSON.stringify({
        metric,
        surface: tags.surface || '',
        scope: tags.scope || '',
        venue: tags.venue || '',
        route: tags.route || '',
        status: tags.status || '',
    });
}

function summarizeFailures(taggedCounters, checksByName) {
    const counterRows = [...taggedCounters.entries()]
        .map(([key, count]) => ({ ...JSON.parse(key), count }))
        .filter((row) => row.count > 0 && failureMetricNames.has(row.metric))
        .sort((a, b) => a.metric.localeCompare(b.metric) || a.surface.localeCompare(b.surface) || a.route.localeCompare(b.route));
    const failedChecks = [...checksByName.entries()]
        .map(([check, value]) => ({ check, ...value }))
        .filter((row) => row.failed > 0)
        .sort((a, b) => b.failed - a.failed || a.check.localeCompare(b.check));
    const failedMutations = counterRows.filter((row) => row.metric === 'profile_live_failed_mutations');
    const missedOwnInvalidations = counterRows.filter((row) => row.metric === 'profile_live_missed_own_invalidations');
    return {
        counters: counterRows,
        failedChecks,
        hints: failureHints(failedMutations, missedOwnInvalidations),
    };
}

function failureHints(failedMutations, missedOwnInvalidations) {
    if (failedMutations.length > 0 && missedOwnInvalidations.length === 0) {
        return ['Mutation failures were recorded, but missed-own-invalidation counters stayed clear; inspect the failed route/status first.'];
    }
    if (failedMutations.length > 0 && missedOwnInvalidations.length > 0) {
        return ['Mutation failures and missed own invalidations both occurred; separate failed requests from successful requests that missed delivery.'];
    }
    if (failedMutations.length === 0 && missedOwnInvalidations.length > 0) {
        return ['Successful mutations missed own invalidations; inspect scope/resource dependencies, source client ids, websocket lifetime, and transport fanout.'];
    }
    return ['No failed mutation or missed own-invalidation counters were recorded.'];
}

function trendSummary(values) {
    return {
        count: values.length,
        medianMs: round(percentile(values, 0.5)),
        p95Ms: round(percentile(values, 0.95)),
        p99Ms: round(percentile(values, 0.99)),
        maxMs: round(values.length ? Math.max(...values) : 0),
    };
}

function percentile(values, ratio) {
    if (values.length === 0) return 0;
    const sorted = [...values].sort((a, b) => a - b);
    const index = Math.min(sorted.length - 1, Math.ceil(sorted.length * ratio) - 1);
    return sorted[index];
}

function avg(values) {
    return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : 0;
}

function max(values) {
    return values.length ? Math.max(...values) : 0;
}

function round(value) {
    return Math.round(value * 10) / 10;
}

function renderMarkdown(metadata, summary) {
    const rows = [
        '# Live Load Profile',
        '',
        '## Agent Snapshot',
        '',
        `- Scenario \`${metadata.scenario ?? ''}\`, subscribers \`${metadata.subscribers ?? ''}\`, mutators \`${metadata.mutators ?? ''}\`, venues \`${metadata.venues ?? ''}\`, weeks \`${metadata.weeks ?? ''}\`.`,
        `- Checks failed \`${summary.checks.failed}/${summary.checks.total}\`; mutations \`${summary.rates.mutationCount}\` at burst \`${summary.rates.mutationBurstRatePerSec}/s\`; invalidations \`${summary.rates.invalidationCount}\` at delivery-window \`${summary.rates.invalidationDeliveryRatePerSec}/s\`.`,
        `- Own invalidations \`${summary.rates.ownInvalidationCount}/${summary.rates.mutationCount}\`; failed mutations \`${summary.counters.profile_live_failed_mutations ?? 0}\`; missed own invalidations \`${summary.counters.profile_live_missed_own_invalidations ?? 0}\`.`,
        `- Own latency p95 \`${summary.trends.profile_live_own_invalidation_latency?.p95Ms ?? 0}ms\`; mutation p95 \`${summary.trends.profile_live_mutation_duration?.p95Ms ?? 0}ms\`.`,
        `- Slowest server labels: ${compactLabels(summary.serverInvalidation.slowestLabels, 'p95TotalMs')}.`,
        `- Highest fanout labels: ${compactLabels(summary.serverInvalidation.highestFanoutLabels, 'maxSubscribers')}.`,
        '',
        '## Run',
        '',
        `Scenario: \`${metadata.scenario ?? ''}\``,
        `Subscribers: \`${metadata.subscribers ?? ''}\``,
        `Mutators: \`${metadata.mutators ?? ''}\``,
        `Venues: \`${metadata.venues ?? ''}\``,
        `Weeks: \`${metadata.weeks ?? ''}\``,
        `Database: \`${metadata.database ?? ''}\``,
        '',
        '## Rates',
        '',
        '| Metric | Value |',
        '| --- | ---: |',
        `| Run duration | ${summary.rates.runDurationSec}s |`,
        `| Mutations | ${summary.rates.mutationCount} |`,
        `| Mutations/sec over run | ${summary.rates.mutationRatePerSec} |`,
        `| Mutation burst window | ${summary.rates.mutationBurstWindowSec}s |`,
        `| Mutation burst/sec | ${summary.rates.mutationBurstRatePerSec} |`,
        `| Invalidations received | ${summary.rates.invalidationCount} |`,
        `| Invalidations/sec over run | ${summary.rates.invalidationRatePerSec} |`,
        `| Invalidation delivery window | ${summary.rates.invalidationDeliveryWindowSec}s |`,
        `| Invalidations/sec during delivery | ${summary.rates.invalidationDeliveryRatePerSec} |`,
        `| Own invalidations | ${summary.rates.ownInvalidationCount} |`,
        `| Own invalidations/sec during burst | ${summary.rates.ownInvalidationBurstRatePerSec} |`,
        '',
        '## Failure Summary',
        '',
        ...summary.failureSummary.hints.map((hint) => `- ${hint}`),
        '',
        '| Metric | Surface | Scope | Venue | Route | Status | Count |',
        '| --- | --- | --- | --- | --- | --- | ---: |',
        ...summary.failureSummary.counters.map((row) => `| \`${row.metric}\` | \`${row.surface}\` | \`${row.scope}\` | \`${row.venue}\` | \`${row.route}\` | \`${row.status}\` | ${row.count} |`),
        '',
        '| Failed Check | Failed | Total |',
        '| --- | ---: | ---: |',
        ...summary.failureSummary.failedChecks.map((row) => `| \`${row.check}\` | ${row.failed} | ${row.total} |`),
        '',
        '## Mutation Timing By Surface',
        '',
        '| Surface | Count | Median | P95 | P99 | Max |',
        '| --- | ---: | ---: | ---: | ---: | ---: |',
        ...summary.mutationsBySurface.map((row) => `| \`${row.surface}\` | ${row.count} | ${row.medianMs} | ${row.p95Ms} | ${row.p99Ms} | ${row.maxMs} |`),
        '',
        '## Server Invalidation Labels',
        '',
        '| Label | Count | Avg Total | P95 Total | Max Total | Avg Plan | Avg Broadcast | Avg Active Scopes | Avg Fragments | Avg Subscribers | Max Subscribers |',
        '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
        ...summary.serverInvalidation.labels.map((row) => `| \`${row.label}\` | ${row.count} | ${row.avgTotalMs} | ${row.p95TotalMs} | ${row.maxTotalMs} | ${row.avgPlanMs} | ${row.avgBroadcastMs} | ${row.avgActiveScopes} | ${row.avgFragments} | ${row.avgSubscribers} | ${row.maxSubscribers} |`),
        '',
        '## Counters',
        '',
        '| Metric | Count |',
        '| --- | ---: |',
        ...Object.entries(summary.counters).map(([name, value]) => `| \`${name}\` | ${value} |`),
        '',
        '## Counters By Surface',
        '',
        '| Metric | Surface | Scope | Venue | Route | Status | Count |',
        '| --- | --- | --- | --- | --- | --- | ---: |',
        ...summary.taggedCounters.map((row) => `| \`${row.metric}\` | \`${row.surface}\` | \`${row.scope}\` | \`${row.venue}\` | \`${row.route}\` | \`${row.status}\` | ${row.count} |`),
        '',
        '## Trends',
        '',
        '| Metric | Count | Median | P95 | P99 | Max |',
        '| --- | ---: | ---: | ---: | ---: | ---: |',
        ...Object.entries(summary.trends).map(([name, value]) => `| \`${name}\` | ${value.count} | ${value.medianMs} | ${value.p95Ms} | ${value.p99Ms} | ${value.maxMs} |`),
        '',
        '## Trends By Surface',
        '',
        '| Metric | Surface | Scope | Venue | Route | Status | Count | Median | P95 | P99 | Max |',
        '| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |',
        ...summary.taggedTrends.map((row) => `| \`${row.metric}\` | \`${row.surface}\` | \`${row.scope}\` | \`${row.venue}\` | \`${row.route}\` | \`${row.status}\` | ${row.count} | ${row.medianMs} | ${row.p95Ms} | ${row.p99Ms} | ${row.maxMs} |`),
        '',
        '## Checks',
        '',
        `Failed checks: \`${summary.checks.failed}/${summary.checks.total}\``,
        '',
        '| Check | Failed | Total |',
        '| --- | ---: | ---: |',
        ...Object.entries(summary.checks.byName).map(([name, value]) => `| \`${name}\` | ${value.failed} | ${value.total} |`),
        '',
        '## HTTP Statuses',
        '',
        '| Route:Status | Count |',
        '| --- | ---: |',
        ...Object.entries(summary.httpStatuses).map(([name, value]) => `| \`${name}\` | ${value} |`),
        '',
    ];
    return rows.join('\n');
}

function compactLabels(rows, valueKey) {
    if (!rows.length) return '`none`';
    return rows.slice(0, 3).map((row) => `\`${row.label}\` ${row[valueKey]}`).join(', ');
}

function groupBy(rows, keyFn) {
    const groups = new Map();
    for (const row of rows) {
        const key = keyFn(row);
        if (!groups.has(key)) groups.set(key, []);
        groups.get(key).push(row);
    }
    return groups;
}
