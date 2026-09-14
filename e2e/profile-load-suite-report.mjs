#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

function usage() {
    console.log(`Usage:
  node e2e/profile-load-suite-report.mjs <suite-output-dir> <scenario-name>...
`);
}

function readJson(filePath) {
    return JSON.parse(fs.readFileSync(path.resolve(filePath), 'utf8'));
}

function round(value) {
    return Math.round(value * 10) / 10;
}

function formatBytes(bytes) {
    if (!Number.isFinite(bytes)) return '?';
    if (bytes >= 1024 * 1024) return `${round(bytes / (1024 * 1024))} MiB`;
    if (bytes >= 1024) return `${round(bytes / 1024)} KiB`;
    return `${round(bytes)} B`;
}

function scenarioProfile(suiteDir, scenario) {
    const profilePath = path.join(suiteDir, scenario, 'load-profile.json');
    const profile = readJson(profilePath);
    return {
        scenario,
        profilePath,
        metadata: profile.metadata || {},
        summary: profile.summary || {},
    };
}

function topItem(items, field) {
    return [...(items || [])].sort((a, b) => (b[field] || 0) - (a[field] || 0))[0] || null;
}

function renderMarkdown(suiteDir, profiles) {
    const seed = profiles[0]?.metadata?.seed || {};
    const totalRequests = profiles.reduce((sum, item) => sum + (item.summary.requestCount || 0), 0);
    const totalFailures = profiles.reduce((sum, item) => sum + (item.summary.failedCount || 0), 0);
    const totalDroppedIterations = profiles.reduce((sum, item) => sum + (item.summary.droppedIterations || 0), 0);
    const totalFailedChecks = profiles.reduce((sum, item) => sum + (item.summary.failedChecks || 0), 0);
    const totalChecks = profiles.reduce((sum, item) => sum + (item.summary.checkCount || 0), 0);
    const missingServerTiming = profiles.flatMap((item) =>
        (item.summary.missingServerTiming || []).map((row) => ({ scenario: item.scenario, ...row }))
    ).sort((a, b) => (b.missingCount || 0) - (a.missingCount || 0));
    const slowestHttp = profiles.flatMap((item) =>
        (item.summary.http || []).map((row) => ({ scenario: item.scenario, ...row }))
    ).sort((a, b) => (b.p95Ms || 0) - (a.p95Ms || 0));
    const slowestAppTotals = profiles.flatMap((item) =>
        (item.summary.appTotals || []).map((row) => ({ scenario: item.scenario, ...row }))
    ).sort((a, b) => (b.p95Ms || 0) - (a.p95Ms || 0));
    const attributionGaps = profiles.flatMap((item) =>
        (item.summary.unattributedAppTotals || []).map((row) => ({ scenario: item.scenario, ...row }))
    ).sort((a, b) => (b.p95Ms || 0) - (a.p95Ms || 0));
    const largestResponses = profiles.flatMap((item) =>
        (item.summary.responseBytes || []).map((row) => ({ scenario: item.scenario, ...row }))
    ).sort((a, b) => (b.p95Bytes || 0) - (a.p95Bytes || 0));
    const componentBytes = profiles.flatMap((item) =>
        (item.summary.componentBytes || []).map((row) => ({ scenario: item.scenario, ...row }))
    ).sort((a, b) => (b.p95Bytes || 0) - (a.p95Bytes || 0));
    const slowestSpanCategories = profiles.flatMap((item) =>
        (item.summary.spanCategories || []).map((row) => ({ scenario: item.scenario, ...row }))
    ).sort((a, b) => (b.p95Ms || 0) - (a.p95Ms || 0));
    const slowestSpans = profiles.flatMap((item) =>
        (item.summary.spans || []).map((row) => ({ scenario: item.scenario, ...row }))
    ).sort((a, b) => (b.p95Ms || 0) - (a.p95Ms || 0));

    const lines = [
        '# Load Profile Suite',
        '',
        `Suite: \`${suiteDir}\``,
        `Scenarios: ${profiles.map((item) => `\`${item.scenario}\``).join(', ')}`,
        '',
        '## Dataset',
        '',
        `Venues: ${seed.venues ?? '?'}`,
        `Staff per venue: ${seed.staffPerVenue ?? '?'}`,
        `History weeks: ${seed.weeksHistory ?? '?'}`,
        `Future weeks: ${seed.weeksFuture ?? '?'}`,
        `Roster rows/day: ${seed.rowsPerDay ?? '?'}`,
        '',
        '## Suite Overview',
        '',
        `Total requests: ${totalRequests}`,
        `Failed 5xx/transport-ish requests: ${totalFailures}`,
        `Dropped iterations: ${totalDroppedIterations}`,
        `Failed checks: ${totalFailedChecks}/${totalChecks}`,
        '',
        '## Timing Coverage Anomalies',
        '',
        ...(missingServerTiming.length === 0
            ? ['No sampled routes were missing `Server-Timing` records.', '']
            : [
                '| Scenario | Route | Requests | App Total Records | Missing |',
                '| --- | --- | ---: | ---: | ---: |',
                ...missingServerTiming.slice(0, 30).map((row) =>
                    `| ${row.scenario} | \`${row.route}\` | ${row.requestCount} | ${row.appTotalCount} | ${row.missingCount} |`
                ),
                '',
            ]),
        '| Scenario | Rate | Duration | Requests | Req/sec | Failures | Dropped | Drop Class | VU Sat. | Slowest HTTP P95 | Slowest App P95 | Worst Unattr. P95 | Slowest Span P95 |',
        '| --- | ---: | --- | ---: | ---: | ---: | ---: | --- | ---: | --- | --- | --- | --- |',
        ...profiles.map((item) => {
            const http = topItem(item.summary.http, 'p95Ms');
            const app = topItem(item.summary.appTotals, 'p95Ms');
            const unattr = topItem(item.summary.unattributedAppTotals, 'p95Ms');
            const span = topItem(item.summary.spans, 'p95Ms');
            return [
                `| \`${item.scenario}\``,
                item.metadata.rate || '?',
                item.metadata.duration || '?',
                item.summary.requestCount || 0,
                item.summary.requestsPerSecond || 0,
                item.summary.failedCount || 0,
                item.summary.droppedIterations || 0,
                item.summary.dropClassification || '?',
                `${round((item.summary.vuSaturation || 0) * 100)}%`,
                http ? `\`${http.route}\` ${http.p95Ms}ms` : '',
                app ? `\`${app.route}\` ${app.p95Ms}ms` : '',
                unattr ? `\`${unattr.route}\` ${unattr.p95Ms}ms` : '',
                span ? `\`${span.span}\` ${span.p95Ms}ms` : '',
            ].join(' | ') + ' |';
        }),
        '',
        '## Slowest HTTP Routes',
        '',
        '| Scenario | Route | Count | Median | P95 | P99 | Max | Statuses |',
        '| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |',
        ...slowestHttp.slice(0, 20).map((row) =>
            `| ${row.scenario} | \`${row.route}\` | ${row.count} | ${row.medianMs} | ${row.p95Ms} | ${row.p99Ms} | ${row.maxMs} | \`${JSON.stringify(row.statuses)}\` |`
        ),
        '',
        '## Slowest App Totals',
        '',
        '| Scenario | Route | Count | Median | P95 | P99 | Max |',
        '| --- | --- | ---: | ---: | ---: | ---: | ---: |',
        ...slowestAppTotals.slice(0, 20).map((row) =>
            `| ${row.scenario} | \`${row.route}\` | ${row.count} | ${row.medianMs} | ${row.p95Ms} | ${row.p99Ms} | ${row.maxMs} |`
        ),
        '',
        '## Largest Attribution Gaps',
        '',
        '| Scenario | Route | Count | Unattributed P95 | Unattributed P99 | Max |',
        '| --- | --- | ---: | ---: | ---: | ---: |',
        ...attributionGaps.slice(0, 20).map((row) =>
            `| ${row.scenario} | \`${row.route}\` | ${row.count} | ${row.p95Ms} | ${row.p99Ms} | ${row.maxMs} |`
        ),
        '',
        '## Largest Responses',
        '',
        '| Scenario | Route | Count | Median | P95 | P99 | Max |',
        '| --- | --- | ---: | ---: | ---: | ---: | ---: |',
        ...largestResponses.slice(0, 20).map((row) =>
            `| ${row.scenario} | \`${row.route}\` | ${row.count} | ${formatBytes(row.medianBytes)} | ${formatBytes(row.p95Bytes)} | ${formatBytes(row.p99Bytes)} | ${formatBytes(row.maxBytes)} |`
        ),
        '',
        '## Component Bytes',
        '',
        '| Scenario | Route | Component | Count | Median | P95 | P99 | Max |',
        '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |',
        ...componentBytes.slice(0, 50).map((row) =>
            `| ${row.scenario} | \`${row.route}\` | \`${row.span}\` | ${row.count} | ${formatBytes(row.medianBytes)} | ${formatBytes(row.p95Bytes)} | ${formatBytes(row.p99Bytes)} | ${formatBytes(row.maxBytes)} |`
        ),
        '',
        '## Slowest Span Categories',
        '',
        '| Scenario | Route | Category | Count | Median | P95 | P99 | Max |',
        '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |',
        ...slowestSpanCategories.slice(0, 30).map((row) =>
            `| ${row.scenario} | \`${row.route}\` | \`${row.category}\` | ${row.count} | ${row.medianMs} | ${row.p95Ms} | ${row.p99Ms} | ${row.maxMs} |`
        ),
        '',
        '## Slowest App Spans',
        '',
        '| Scenario | Route | Category | Span | Count | Median | P95 | P99 | Max |',
        '| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |',
        ...slowestSpans.slice(0, 30).map((row) =>
            `| ${row.scenario} | \`${row.route}\` | \`${row.category || ''}\` | \`${row.span}\` | ${row.count} | ${row.medianMs} | ${row.p95Ms} | ${row.p99Ms} | ${row.maxMs} |`
        ),
        '',
    ];

    return `${lines.join('\n')}\n`;
}

function main() {
    const [suiteDirArg, ...scenarios] = process.argv.slice(2);
    if (!suiteDirArg || scenarios.length === 0) {
        usage();
        process.exit(1);
    }

    const suiteDir = path.resolve(suiteDirArg);
    const profiles = scenarios.map((scenario) => scenarioProfile(suiteDir, scenario));
    const summary = {
        suiteDir,
        scenarios: profiles.map((item) => ({
            scenario: item.scenario,
            metadata: item.metadata,
            summary: item.summary,
        })),
    };

    fs.writeFileSync(path.join(suiteDir, 'suite-summary.json'), `${JSON.stringify(summary, null, 2)}\n`);
    fs.writeFileSync(path.join(suiteDir, 'suite-summary.md'), renderMarkdown(suiteDir, profiles));
    console.log(`Load profile suite summary: ${path.join(suiteDir, 'suite-summary.md')}`);
}

main();
