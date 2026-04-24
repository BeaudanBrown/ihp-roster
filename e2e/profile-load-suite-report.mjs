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
    const slowestHttp = profiles.flatMap((item) =>
        (item.summary.http || []).map((row) => ({ scenario: item.scenario, ...row }))
    ).sort((a, b) => (b.p95Ms || 0) - (a.p95Ms || 0));
    const slowestAppTotals = profiles.flatMap((item) =>
        (item.summary.appTotals || []).map((row) => ({ scenario: item.scenario, ...row }))
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
        '',
        '| Scenario | Rate | Duration | Requests | Req/sec | Failures | Slowest HTTP P95 | Slowest App P95 | Slowest Span P95 |',
        '| --- | ---: | --- | ---: | ---: | ---: | --- | --- | --- |',
        ...profiles.map((item) => {
            const http = topItem(item.summary.http, 'p95Ms');
            const app = topItem(item.summary.appTotals, 'p95Ms');
            const span = topItem(item.summary.spans, 'p95Ms');
            return [
                `| \`${item.scenario}\``,
                item.metadata.rate || '?',
                item.metadata.duration || '?',
                item.summary.requestCount || 0,
                item.summary.requestsPerSecond || 0,
                item.summary.failedCount || 0,
                http ? `\`${http.route}\` ${http.p95Ms}ms` : '',
                app ? `\`${app.route}\` ${app.p95Ms}ms` : '',
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
        '## Slowest App Spans',
        '',
        '| Scenario | Route | Span | Count | Median | P95 | P99 | Max |',
        '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |',
        ...slowestSpans.slice(0, 30).map((row) =>
            `| ${row.scenario} | \`${row.route}\` | \`${row.span}\` | ${row.count} | ${row.medianMs} | ${row.p95Ms} | ${row.p99Ms} | ${row.maxMs} |`
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
