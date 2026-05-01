#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

function usage() {
    console.log(`Usage:
  node e2e/profile-load-report.mjs <k6-metrics.ndjson> <output-dir> [metadata.json]
`);
}

function readJson(filePath) {
    return JSON.parse(fs.readFileSync(path.resolve(filePath), 'utf8'));
}

function percentile(values, ratio) {
    if (values.length === 0) return 0;
    const sorted = [...values].sort((a, b) => a - b);
    const index = Math.min(sorted.length - 1, Math.ceil(sorted.length * ratio) - 1);
    return sorted[index];
}

function round(value) {
    return Math.round(value * 10) / 10;
}

function groupKey(tags, names) {
    return names.map((name) => tags?.[name] || '').join('::');
}

function ensureGroup(map, key, init) {
    if (!map.has(key)) map.set(key, init());
    return map.get(key);
}

function summarizeSamples(samples) {
    return {
        count: samples.length,
        medianMs: round(percentile(samples, 0.5)),
        p95Ms: round(percentile(samples, 0.95)),
        p99Ms: round(percentile(samples, 0.99)),
        maxMs: round(samples.length ? Math.max(...samples) : 0),
    };
}

function parseMetrics(filePath) {
    const httpGroups = new Map();
    const appGroups = new Map();
    const spanGroups = new Map();
    let requestCount = 0;
    let failedCount = 0;
    let droppedIterations = 0;
    let completedIterations = 0;
    let checkCount = 0;
    let failedChecks = 0;
    let maxObservedVus = 0;
    let maxObservedVusLimit = 0;
    let firstTime = null;
    let lastTime = null;

    const content = fs.readFileSync(path.resolve(filePath), 'utf8');
    for (const line of content.split('\n')) {
        if (!line.trim()) continue;
        const event = JSON.parse(line);
        if (event.type !== 'Point') continue;

        const data = event.data || {};
        const tags = data.tags || {};
        const value = Number(data.value);
        if (!Number.isFinite(value)) continue;

        if (data.time) {
            const time = Date.parse(data.time);
            if (Number.isFinite(time)) {
                firstTime = firstTime === null ? time : Math.min(firstTime, time);
                lastTime = lastTime === null ? time : Math.max(lastTime, time);
            }
        }

        if (event.metric === 'http_req_duration') {
            requestCount += 1;
            if (String(tags.status || '').startsWith('5') || String(tags.status || '') === '0') failedCount += 1;
            const key = groupKey(tags, ['scenario', 'route']);
            const group = ensureGroup(httpGroups, key, () => ({
                scenario: tags.scenario || '',
                route: tags.route || '',
                samples: [],
                statuses: new Map(),
            }));
            group.samples.push(value);
            const status = String(tags.status || 'unknown');
            group.statuses.set(status, (group.statuses.get(status) || 0) + 1);
        } else if (event.metric === 'profile_request_app_total') {
            const key = groupKey(tags, ['scenario', 'route']);
            const group = ensureGroup(appGroups, key, () => ({
                scenario: tags.scenario || '',
                route: tags.route || '',
                samples: [],
            }));
            group.samples.push(value);
        } else if (event.metric === 'profile_span_duration') {
            const key = groupKey(tags, ['scenario', 'route', 'span']);
            const group = ensureGroup(spanGroups, key, () => ({
                scenario: tags.scenario || '',
                route: tags.route || '',
                span: tags.span || '',
                samples: [],
            }));
            group.samples.push(value);
        } else if (event.metric === 'dropped_iterations') {
            droppedIterations += value;
        } else if (event.metric === 'iterations') {
            completedIterations += value;
        } else if (event.metric === 'checks') {
            checkCount += 1;
            if (value === 0) failedChecks += 1;
        } else if (event.metric === 'vus') {
            maxObservedVus = Math.max(maxObservedVus, value);
        } else if (event.metric === 'vus_max') {
            maxObservedVusLimit = Math.max(maxObservedVusLimit, value);
        }
    }

    const elapsedSeconds = firstTime !== null && lastTime !== null
        ? Math.max((lastTime - firstTime) / 1000, 0.001)
        : 0;

    const http = [...httpGroups.values()].map((group) => ({
        scenario: group.scenario,
        route: group.route,
        statuses: Object.fromEntries(group.statuses),
        ...summarizeSamples(group.samples),
    })).sort((a, b) => b.p95Ms - a.p95Ms);

    const appTotals = [...appGroups.values()].map((group) => ({
        scenario: group.scenario,
        route: group.route,
        ...summarizeSamples(group.samples),
    })).sort((a, b) => b.p95Ms - a.p95Ms);

    const spans = [...spanGroups.values()].map((group) => ({
        scenario: group.scenario,
        route: group.route,
        span: group.span,
        ...summarizeSamples(group.samples),
    })).sort((a, b) => b.p95Ms - a.p95Ms);

    return {
        requestCount,
        failedCount,
        failureRate: requestCount === 0 ? 0 : failedCount / requestCount,
        droppedIterations,
        completedIterations,
        checkCount,
        failedChecks,
        checkFailureRate: checkCount === 0 ? 0 : failedChecks / checkCount,
        maxObservedVus,
        maxObservedVusLimit,
        vuSaturation: maxObservedVusLimit === 0 ? 0 : round(maxObservedVus / maxObservedVusLimit),
        elapsedSeconds: round(elapsedSeconds),
        requestsPerSecond: elapsedSeconds === 0 ? 0 : round(requestCount / elapsedSeconds),
        http,
        appTotals,
        spans,
    };
}

function renderMarkdown(summary, metadata) {
    const seed = metadata.seed || {};
    const lines = [
        '# Load Profile',
        '',
        `Run ID: \`${metadata.runId || 'unknown'}\``,
        `Scenario: \`${metadata.scenario || 'unknown'}\``,
        `Load: ${metadata.rate || '?'} iterations/sec for ${metadata.duration || '?'}; preallocated VUs ${metadata.vus || '?'}, max VUs ${metadata.maxVus || '?'}`,
        `Database: \`${metadata.database || 'unknown'}\``,
        '',
        '## Dataset',
        '',
        `Venues: ${seed.venues ?? '?'}`,
        `Staff per venue: ${seed.staffPerVenue ?? '?'}`,
        `History weeks: ${seed.weeksHistory ?? '?'}`,
        `Future weeks: ${seed.weeksFuture ?? '?'}`,
        `Roster rows/day: ${seed.rowsPerDay ?? '?'}`,
        '',
        '## HTTP Overview',
        '',
        `Requests: ${summary.requestCount}`,
        `Failed 5xx/transport-ish requests: ${summary.failedCount} (${round(summary.failureRate * 100)}%)`,
        `Completed iterations: ${summary.completedIterations}`,
        `Dropped iterations: ${summary.droppedIterations}`,
        `Failed checks: ${summary.failedChecks}/${summary.checkCount} (${round(summary.checkFailureRate * 100)}%)`,
        `Max observed VUs: ${summary.maxObservedVus}/${summary.maxObservedVusLimit || '?'} (${round(summary.vuSaturation * 100)}%)`,
        `Observed throughput: ${summary.requestsPerSecond} req/sec over ${summary.elapsedSeconds}s`,
        '',
        '## Slowest HTTP Routes',
        '',
        '| Scenario | Route | Count | Median | P95 | P99 | Max | Statuses |',
        '| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |',
        ...summary.http.slice(0, 20).map((row) =>
            `| ${row.scenario} | \`${row.route}\` | ${row.count} | ${row.medianMs} | ${row.p95Ms} | ${row.p99Ms} | ${row.maxMs} | \`${JSON.stringify(row.statuses)}\` |`
        ),
        '',
        '## Slowest App Totals',
        '',
        '| Scenario | Route | Count | Median | P95 | P99 | Max |',
        '| --- | --- | ---: | ---: | ---: | ---: | ---: |',
        ...summary.appTotals.slice(0, 20).map((row) =>
            `| ${row.scenario} | \`${row.route}\` | ${row.count} | ${row.medianMs} | ${row.p95Ms} | ${row.p99Ms} | ${row.maxMs} |`
        ),
        '',
        '## Slowest App Spans',
        '',
        '| Scenario | Route | Span | Count | Median | P95 | P99 | Max |',
        '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |',
        ...summary.spans.slice(0, 30).map((row) =>
            `| ${row.scenario} | \`${row.route}\` | \`${row.span}\` | ${row.count} | ${row.medianMs} | ${row.p95Ms} | ${row.p99Ms} | ${row.maxMs} |`
        ),
        '',
    ];

    return `${lines.join('\n')}\n`;
}

function main() {
    const [metricsPath, outputDir, metadataPath] = process.argv.slice(2);
    if (!metricsPath || !outputDir) {
        usage();
        process.exit(1);
    }

    const resolvedOutputDir = path.resolve(outputDir);
    const metadata = metadataPath ? readJson(metadataPath) : {};
    const summary = parseMetrics(metricsPath);
    const profile = { metadata, summary };
    const markdown = renderMarkdown(summary, metadata);

    fs.mkdirSync(resolvedOutputDir, { recursive: true });
    fs.writeFileSync(path.join(resolvedOutputDir, 'load-profile.json'), `${JSON.stringify(profile, null, 2)}\n`);
    fs.writeFileSync(path.join(resolvedOutputDir, 'load-profile.md'), markdown);
    console.log(`Load profile artifacts: ${resolvedOutputDir}`);
}

main();
