#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

function printUsage() {
    console.log(`Usage:
  node e2e/profile-compare.mjs <before-profile.json> <after-profile.json> [output.md]
`);
}

function readProfile(filePath) {
    return JSON.parse(fs.readFileSync(path.resolve(filePath), 'utf8'));
}

function spanKey(span) {
    return `${span.scenario}::${span.route || ''}::${span.span}`;
}

function requestKey(request) {
    return `${request.scenario}::${request.method || ''}::${request.route || request.path}`;
}

function indexBy(items, keyFn) {
    const result = new Map();
    for (const item of items) result.set(keyFn(item), item);
    return result;
}

function diffValue(before, after) {
    const delta = Math.round((after - before) * 10) / 10;
    const percent = before === 0 ? null : Math.round((delta / before) * 1000) / 10;
    return { delta, percent };
}

function compare(beforeProfile, afterProfile) {
    const before = normalizeProfile(beforeProfile);
    const after = normalizeProfile(afterProfile);
    const beforeSpans = indexBy(before.spans, spanKey);
    const afterSpans = indexBy(after.spans, spanKey);
    const beforeRequests = indexBy(before.requests, requestKey);
    const afterRequests = indexBy(after.requests, requestKey);
    const beforeScenarioStats = indexBy(before.scenarios, (item) => item.scenario);
    const afterScenarioStats = indexBy(after.scenarios, (item) => item.scenario);

    const spanDiffs = [...afterSpans.entries()]
        .filter(([key]) => beforeSpans.has(key))
        .map(([key, after]) => {
            const before = beforeSpans.get(key);
            const p95 = diffValue(before.p95Ms, after.p95Ms);
            const median = diffValue(before.medianMs, after.medianMs);
            return { key, scenario: after.scenario, route: after.route || '', span: after.span, before, after, p95, median };
        })
        .sort((a, b) => Math.abs(b.p95.delta) - Math.abs(a.p95.delta));

    const requestDiffs = [...afterRequests.entries()]
        .filter(([key]) => beforeRequests.has(key))
        .map(([key, after]) => {
            const before = beforeRequests.get(key);
            const beforeValue = before.totalMs ?? before.p95Ms;
            const afterValue = after.totalMs ?? after.p95Ms;
            const total = diffValue(beforeValue, afterValue);
            return { key, scenario: after.scenario, method: after.method || '', path: after.path || after.route, before, after, total };
        })
        .sort((a, b) => Math.abs(b.total.delta) - Math.abs(a.total.delta));

    const scenarioDiffs = [...afterScenarioStats.entries()]
        .filter(([key]) => beforeScenarioStats.has(key))
        .map(([key, after]) => {
            const before = beforeScenarioStats.get(key);
            return {
                key,
                scenario: after.scenario,
                before,
                after,
                droppedIterations: diffValue(before.droppedIterations || 0, after.droppedIterations || 0),
                failureRate: diffValue(before.failureRate || 0, after.failureRate || 0),
                vuSaturation: diffValue(before.vuSaturation || 0, after.vuSaturation || 0),
            };
        })
        .sort((a, b) => Math.abs(b.droppedIterations.delta) - Math.abs(a.droppedIterations.delta));

    return { spanDiffs, requestDiffs, scenarioDiffs };
}

function normalizeProfile(profile) {
    if (Array.isArray(profile.scenarios)) {
        const summaries = profile.scenarios.map((item) => ({ scenario: item.scenario, ...(item.summary || {}) }));
        return {
            requests: summaries.flatMap((summary) => (summary.http || []).map((row) => ({ scenario: summary.scenario, ...row }))),
            spans: summaries.flatMap((summary) => (summary.spans || []).map((row) => ({ scenario: summary.scenario, ...row }))),
            scenarios: summaries,
        };
    }

    const summary = profile.summary || {};
    if (summary.http || summary.appTotals || summary.spans) {
        const scenario = profile.metadata?.scenario || summary.scenario || 'profile-load';
        return {
            requests: (summary.http || []).map((row) => ({ scenario, ...row })),
            spans: (summary.spans || []).map((row) => ({ scenario, ...row })),
            scenarios: [{ scenario, ...summary }],
        };
    }

    return {
        requests: summary.slowestRequests || [],
        spans: summary.slowestSpans || [],
        scenarios: [],
    };
}

function formatDelta(diff) {
    const percent = diff.percent === null ? '' : ` (${diff.percent >= 0 ? '+' : ''}${diff.percent}%)`;
    return `${diff.delta >= 0 ? '+' : ''}${diff.delta}${percent}`;
}

function renderMarkdown(beforePath, afterPath, comparison) {
    const lines = [
        '# Profile Comparison',
        '',
        `Before: \`${beforePath}\``,
        `After: \`${afterPath}\``,
        '',
        '## Largest Span Changes',
        '',
        '| Scenario | Route | Span | Before P95 | After P95 | Delta P95 | Before Median | After Median | Delta Median |',
        '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |',
        ...comparison.spanDiffs.slice(0, 30).map((item) =>
            `| ${item.scenario} | \`${item.route}\` | \`${item.span}\` | ${item.before.p95Ms} | ${item.after.p95Ms} | ${formatDelta(item.p95)} | ${item.before.medianMs} | ${item.after.medianMs} | ${formatDelta(item.median)} |`
        ),
        '',
        '## Largest Request Changes',
        '',
        '| Scenario | Method | Path | Before Total | After Total | Delta |',
        '| --- | --- | --- | ---: | ---: | ---: |',
        ...comparison.requestDiffs.slice(0, 20).map((item) =>
            `| ${item.scenario} | ${item.method} | \`${item.path}\` | ${item.before.totalMs ?? item.before.p95Ms} | ${item.after.totalMs ?? item.after.p95Ms} | ${formatDelta(item.total)} |`
        ),
        '',
        '## Load Pressure Changes',
        '',
        '| Scenario | Before Dropped | After Dropped | Delta Dropped | Before VU Sat. | After VU Sat. | Delta VU Sat. |',
        '| --- | ---: | ---: | ---: | ---: | ---: | ---: |',
        ...comparison.scenarioDiffs.slice(0, 20).map((item) =>
            `| ${item.scenario} | ${item.before.droppedIterations || 0} | ${item.after.droppedIterations || 0} | ${formatDelta(item.droppedIterations)} | ${item.before.vuSaturation || 0} | ${item.after.vuSaturation || 0} | ${formatDelta(item.vuSaturation)} |`
        ),
        '',
    ];
    return `${lines.join('\n')}\n`;
}

function main() {
    const [beforePath, afterPath, outputPath] = process.argv.slice(2);
    if (!beforePath || !afterPath) {
        printUsage();
        process.exit(1);
    }

    const beforeProfile = readProfile(beforePath);
    const afterProfile = readProfile(afterPath);
    const markdown = renderMarkdown(beforePath, afterPath, compare(beforeProfile, afterProfile));

    if (outputPath) {
        const resolvedOutput = path.resolve(outputPath);
        fs.mkdirSync(path.dirname(resolvedOutput), { recursive: true });
        fs.writeFileSync(resolvedOutput, markdown);
        console.log(`Profile comparison: ${resolvedOutput}`);
    } else {
        process.stdout.write(markdown);
    }
}

main();
