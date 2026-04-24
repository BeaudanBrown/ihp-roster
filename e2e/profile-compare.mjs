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
    return `${span.scenario}::${span.span}`;
}

function requestKey(request) {
    return `${request.scenario}::${request.method}::${request.path}`;
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
    const beforeSpans = indexBy(beforeProfile.summary?.slowestSpans || [], spanKey);
    const afterSpans = indexBy(afterProfile.summary?.slowestSpans || [], spanKey);
    const beforeRequests = indexBy(beforeProfile.summary?.slowestRequests || [], requestKey);
    const afterRequests = indexBy(afterProfile.summary?.slowestRequests || [], requestKey);

    const spanDiffs = [...afterSpans.entries()]
        .filter(([key]) => beforeSpans.has(key))
        .map(([key, after]) => {
            const before = beforeSpans.get(key);
            const p95 = diffValue(before.p95Ms, after.p95Ms);
            const median = diffValue(before.medianMs, after.medianMs);
            return { key, scenario: after.scenario, span: after.span, before, after, p95, median };
        })
        .sort((a, b) => Math.abs(b.p95.delta) - Math.abs(a.p95.delta));

    const requestDiffs = [...afterRequests.entries()]
        .filter(([key]) => beforeRequests.has(key))
        .map(([key, after]) => {
            const before = beforeRequests.get(key);
            const total = diffValue(before.totalMs, after.totalMs);
            return { key, scenario: after.scenario, method: after.method, path: after.path, before, after, total };
        })
        .sort((a, b) => Math.abs(b.total.delta) - Math.abs(a.total.delta));

    return { spanDiffs, requestDiffs };
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
        '| Scenario | Span | Before P95 | After P95 | Delta P95 | Before Median | After Median | Delta Median |',
        '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |',
        ...comparison.spanDiffs.slice(0, 30).map((item) =>
            `| ${item.scenario} | \`${item.span}\` | ${item.before.p95Ms} | ${item.after.p95Ms} | ${formatDelta(item.p95)} | ${item.before.medianMs} | ${item.after.medianMs} | ${formatDelta(item.median)} |`
        ),
        '',
        '## Largest Request Changes',
        '',
        '| Scenario | Method | Path | Before Total | After Total | Delta |',
        '| --- | --- | --- | ---: | ---: | ---: |',
        ...comparison.requestDiffs.slice(0, 20).map((item) =>
            `| ${item.scenario} | ${item.method} | \`${item.path}\` | ${item.before.totalMs} | ${item.after.totalMs} | ${formatDelta(item.total)} |`
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
