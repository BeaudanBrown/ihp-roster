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

function evaluateCorrectnessBudget(summary) {
    const catalog = readJson(process.env.PROFILE_BUDGET_CATALOG || 'e2e/profile-regression-budgets.json');
    const budget = catalog.loadCorrectness || {};
    const checks = [
        { name: 'failure rate', actual: summary.failureRate, operator: '<=', limit: budget.maximumFailureRate ?? 0, passed: summary.failureRate <= (budget.maximumFailureRate ?? 0) },
        { name: 'check failure rate', actual: summary.checkFailureRate, operator: '<=', limit: budget.maximumCheckFailureRate ?? 0, passed: summary.checkFailureRate <= (budget.maximumCheckFailureRate ?? 0) },
        { name: 'clean-run drop rate', actual: summary.dropRate, operator: '<', limit: budget.maximumCleanRunDropRate ?? 0.01, passed: summary.dropRate < (budget.maximumCleanRunDropRate ?? 0.01) },
    ];
    return { passed: checks.every((check) => check.passed), checks, latencyBudget: 'matched-baseline-required' };
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

function summarizeSamples(samples, suffix = 'Ms') {
    return {
        count: samples.length,
        [`median${suffix}`]: round(percentile(samples, 0.5)),
        [`p95${suffix}`]: round(percentile(samples, 0.95)),
        [`p99${suffix}`]: round(percentile(samples, 0.99)),
        [`max${suffix}`]: round(samples.length ? Math.max(...samples) : 0),
    };
}

function spanCategory(span) {
    if (!span) return 'unknown';
    if (span.includes('projection')) return 'projection';
    if (span.includes('direct') || span.includes('fetch') || span.includes('load')) return 'read_model';
    if (span.includes('render') || span.startsWith('render_')) return 'render';
    if (span.includes('build') || span.includes('predict') || span.includes('ensure')) return 'domain';
    if (span.includes('live')) return 'live_update';
    if (span.includes('xero')) return 'external';
    return span.split('_')[0] || 'unknown';
}

function dropClassification(dropRate) {
    if (dropRate < 0.01) return 'clean';
    if (dropRate < 0.10) return 'strained';
    return 'overloaded';
}

function formatBytes(bytes) {
    if (!Number.isFinite(bytes)) return '?';
    if (bytes >= 1024 * 1024) return `${round(bytes / (1024 * 1024))} MiB`;
    if (bytes >= 1024) return `${round(bytes / 1024)} KiB`;
    return `${round(bytes)} B`;
}

function parseMetrics(filePath) {
    const httpGroups = new Map();
    const appGroups = new Map();
    const namedSpanGroups = new Map();
    const unattributedGroups = new Map();
    const byteGroups = new Map();
    const spanGroups = new Map();
    const spanCategoryGroups = new Map();
    const componentByteGroups = new Map();
    const counterGroups = new Map();
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
        } else if (event.metric === 'profile_named_span_total') {
            const key = groupKey(tags, ['scenario', 'route']);
            const group = ensureGroup(namedSpanGroups, key, () => ({
                scenario: tags.scenario || '',
                route: tags.route || '',
                samples: [],
            }));
            group.samples.push(value);
        } else if (event.metric === 'profile_unattributed_app_total') {
            const key = groupKey(tags, ['scenario', 'route']);
            const group = ensureGroup(unattributedGroups, key, () => ({
                scenario: tags.scenario || '',
                route: tags.route || '',
                samples: [],
            }));
            group.samples.push(value);
        } else if (event.metric === 'profile_response_bytes') {
            const key = groupKey(tags, ['scenario', 'route']);
            const group = ensureGroup(byteGroups, key, () => ({
                scenario: tags.scenario || '',
                route: tags.route || '',
                samples: [],
            }));
            group.samples.push(value);
        } else if (event.metric === 'profile_component_bytes') {
            const key = groupKey(tags, ['scenario', 'route', 'span']);
            const group = ensureGroup(componentByteGroups, key, () => ({
                scenario: tags.scenario || '',
                route: tags.route || '',
                span: tags.span || '',
                samples: [],
            }));
            group.samples.push(value);
        } else if (event.metric === 'profile_counter_value') {
            const key = groupKey(tags, ['scenario', 'route', 'counter']);
            const group = ensureGroup(counterGroups, key, () => ({
                scenario: tags.scenario || '',
                route: tags.route || '',
                counter: tags.counter || '',
                total: 0,
                samples: [],
            }));
            group.total += value;
            group.samples.push(value);
        } else if (event.metric === 'profile_span_duration') {
            const key = groupKey(tags, ['scenario', 'route', 'span']);
            const group = ensureGroup(spanGroups, key, () => ({
                scenario: tags.scenario || '',
                route: tags.route || '',
                span: tags.span || '',
                category: spanCategory(tags.span || ''),
                samples: [],
            }));
            group.samples.push(value);
            const categoryKey = groupKey({ ...tags, category: group.category }, ['scenario', 'route', 'category']);
            const categoryGroup = ensureGroup(spanCategoryGroups, categoryKey, () => ({
                scenario: tags.scenario || '',
                route: tags.route || '',
                category: group.category,
                samples: [],
            }));
            categoryGroup.samples.push(value);
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

    const namedSpanTotals = [...namedSpanGroups.values()].map((group) => ({
        scenario: group.scenario,
        route: group.route,
        ...summarizeSamples(group.samples),
    })).sort((a, b) => b.p95Ms - a.p95Ms);

    const unattributedAppTotals = [...unattributedGroups.values()].map((group) => ({
        scenario: group.scenario,
        route: group.route,
        ...summarizeSamples(group.samples),
    })).sort((a, b) => b.p95Ms - a.p95Ms);

    const responseBytes = [...byteGroups.values()].map((group) => ({
        scenario: group.scenario,
        route: group.route,
        ...summarizeSamples(group.samples, 'Bytes'),
    })).sort((a, b) => b.p95Bytes - a.p95Bytes);

    const spans = [...spanGroups.values()].map((group) => ({
        scenario: group.scenario,
        route: group.route,
        span: group.span,
        category: group.category,
        ...summarizeSamples(group.samples),
    })).sort((a, b) => b.p95Ms - a.p95Ms);

    const spanCategories = [...spanCategoryGroups.values()].map((group) => ({
        scenario: group.scenario,
        route: group.route,
        category: group.category,
        ...summarizeSamples(group.samples),
    })).sort((a, b) => b.p95Ms - a.p95Ms);

    const componentBytes = [...componentByteGroups.values()].map((group) => ({
        scenario: group.scenario,
        route: group.route,
        span: group.span,
        ...summarizeSamples(group.samples, 'Bytes'),
    })).sort((a, b) => b.p95Bytes - a.p95Bytes);

    const counters = [...counterGroups.values()].map((group) => ({
        scenario: group.scenario,
        route: group.route,
        counter: group.counter,
        total: group.total,
        ...summarizeSamples(group.samples, 'Count'),
    })).sort((a, b) => b.p95Count - a.p95Count || b.total - a.total);

    const missingServerTiming = [...httpGroups.values()]
        .map((group) => {
            const key = groupKey({ scenario: group.scenario, route: group.route }, ['scenario', 'route']);
            const appTotalCount = appGroups.get(key)?.samples.length || 0;
            const missingCount = Math.max(0, group.samples.length - appTotalCount);
            return {
                scenario: group.scenario,
                route: group.route,
                requestCount: group.samples.length,
                appTotalCount,
                missingCount,
            };
        })
        .filter((row) => row.missingCount > 0)
        .sort((a, b) => b.missingCount - a.missingCount || a.route.localeCompare(b.route));

    const scheduledIterations = completedIterations + droppedIterations;
    const dropRate = scheduledIterations === 0 ? 0 : droppedIterations / scheduledIterations;

    const missingResponseBytes = [...httpGroups.values()]
        .map((group) => {
            const key = groupKey({ scenario: group.scenario, route: group.route }, ['scenario', 'route']);
            const byteCount = byteGroups.get(key)?.samples.length || 0;
            const missingCount = Math.max(0, group.samples.length - byteCount);
            return {
                scenario: group.scenario,
                route: group.route,
                requestCount: group.samples.length,
                byteCount,
                missingCount,
            };
        })
        .filter((row) => row.missingCount > 0)
        .sort((a, b) => b.missingCount - a.missingCount || a.route.localeCompare(b.route));

    return {
        requestCount,
        failedCount,
        failureRate: requestCount === 0 ? 0 : failedCount / requestCount,
        droppedIterations,
        completedIterations,
        scheduledIterations,
        dropRate,
        dropClassification: dropClassification(dropRate),
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
        namedSpanTotals,
        unattributedAppTotals,
        responseBytes,
        spans,
        spanCategories,
        componentBytes,
        counters,
        missingServerTiming,
        missingResponseBytes,
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
        '## Regression Budget',
        '',
        `Correctness/clean-run budget: **${summary.regressionBudget.passed ? 'pass' : 'fail'}**. Host-sensitive latency requires a matched baseline.`,
        '',
        '| Check | Actual | Requirement | Result |',
        '| --- | ---: | --- | --- |',
        ...summary.regressionBudget.checks.map((check) => `| ${check.name} | ${round(check.actual)} | ${check.operator} ${check.limit} | ${check.passed ? 'pass' : 'fail'} |`),
        '',
        '## HTTP Overview',
        '',
        `Requests: ${summary.requestCount}`,
        `Failed 5xx/transport-ish requests: ${summary.failedCount} (${round(summary.failureRate * 100)}%)`,
        `Completed iterations: ${summary.completedIterations}`,
        `Dropped iterations: ${summary.droppedIterations}`,
        `Scheduled iterations: ${summary.scheduledIterations} (${round(summary.dropRate * 100)}% dropped; ${summary.dropClassification})`,
        `Failed checks: ${summary.failedChecks}/${summary.checkCount} (${round(summary.checkFailureRate * 100)}%)`,
        `Max observed VUs: ${summary.maxObservedVus}/${summary.maxObservedVusLimit || '?'} (${round(summary.vuSaturation * 100)}%)`,
        `Observed throughput: ${summary.requestsPerSecond} req/sec over ${summary.elapsedSeconds}s`,
        '',
        '## Timing Coverage Anomalies',
        '',
        ...(summary.missingServerTiming.length === 0
            ? ['No sampled routes were missing `Server-Timing` records.', '']
            : [
                '| Scenario | Route | Requests | App Total Records | Missing |',
                '| --- | --- | ---: | ---: | ---: |',
                ...summary.missingServerTiming.map((row) =>
                    `| ${row.scenario} | \`${row.route}\` | ${row.requestCount} | ${row.appTotalCount} | ${row.missingCount} |`
                ),
                '',
            ]),
        ...(summary.missingResponseBytes.length === 0
            ? ['All sampled routes had response byte records.', '']
            : [
                '### Response Size Coverage',
                '',
                '| Scenario | Route | Requests | Byte Records | Missing |',
                '| --- | --- | ---: | ---: | ---: |',
                ...summary.missingResponseBytes.map((row) =>
                    `| ${row.scenario} | \`${row.route}\` | ${row.requestCount} | ${row.byteCount} | ${row.missingCount} |`
                ),
                '',
            ]),
        '## Attribution Gaps',
        '',
        '| Scenario | Route | Count | App P95 | Named Span P95 | Unattributed P95 |',
        '| --- | --- | ---: | ---: | ---: | ---: |',
        ...summary.unattributedAppTotals.slice(0, 20).map((row) => {
            const key = `${row.scenario}::${row.route}`;
            const app = summary.appTotals.find((item) => `${item.scenario}::${item.route}` === key);
            const named = summary.namedSpanTotals.find((item) => `${item.scenario}::${item.route}` === key);
            return `| ${row.scenario} | \`${row.route}\` | ${row.count} | ${app?.p95Ms ?? ''} | ${named?.p95Ms ?? ''} | ${row.p95Ms} |`;
        }),
        '',
        '## Largest Responses',
        '',
        '| Scenario | Route | Count | Median | P95 | P99 | Max |',
        '| --- | --- | ---: | ---: | ---: | ---: | ---: |',
        ...summary.responseBytes.slice(0, 20).map((row) =>
            `| ${row.scenario} | \`${row.route}\` | ${row.count} | ${formatBytes(row.medianBytes)} | ${formatBytes(row.p95Bytes)} | ${formatBytes(row.p99Bytes)} | ${formatBytes(row.maxBytes)} |`
        ),
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
        '## Component Bytes',
        '',
        '| Scenario | Route | Component | Count | Median | P95 | P99 | Max |',
        '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |',
        ...summary.componentBytes.slice(0, 40).map((row) =>
            `| ${row.scenario} | \`${row.route}\` | \`${row.span}\` | ${row.count} | ${formatBytes(row.medianBytes)} | ${formatBytes(row.p95Bytes)} | ${formatBytes(row.p99Bytes)} | ${formatBytes(row.maxBytes)} |`
        ),
        '',
        '## Profile Counters',
        '',
        '| Scenario | Route | Counter | Samples | Total | Median/request | P95/request | Max/request |',
        '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |',
        ...summary.counters.slice(0, 40).map((row) =>
            `| ${row.scenario} | \`${row.route}\` | \`${row.counter}\` | ${row.count} | ${row.total} | ${row.medianCount} | ${row.p95Count} | ${row.maxCount} |`
        ),
        '',
        '## Slowest Span Categories',
        '',
        '| Scenario | Route | Category | Count | Median | P95 | P99 | Max |',
        '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |',
        ...summary.spanCategories.slice(0, 30).map((row) =>
            `| ${row.scenario} | \`${row.route}\` | \`${row.category}\` | ${row.count} | ${row.medianMs} | ${row.p95Ms} | ${row.p99Ms} | ${row.maxMs} |`
        ),
        '',
        '## Slowest App Spans',
        '',
        '| Scenario | Route | Category | Span | Count | Median | P95 | P99 | Max |',
        '| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |',
        ...summary.spans.slice(0, 30).map((row) =>
            `| ${row.scenario} | \`${row.route}\` | \`${row.category}\` | \`${row.span}\` | ${row.count} | ${row.medianMs} | ${row.p95Ms} | ${row.p99Ms} | ${row.maxMs} |`
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
    summary.regressionBudget = evaluateCorrectnessBudget(summary);
    const profile = { metadata, summary };
    const markdown = renderMarkdown(summary, metadata);

    fs.mkdirSync(resolvedOutputDir, { recursive: true });
    fs.writeFileSync(path.join(resolvedOutputDir, 'load-profile.json'), `${JSON.stringify(profile, null, 2)}\n`);
    fs.writeFileSync(path.join(resolvedOutputDir, 'load-profile.md'), markdown);
    console.log(`Load profile artifacts: ${resolvedOutputDir}`);
    if (!summary.regressionBudget.passed) process.exitCode = 2;
}

main();
