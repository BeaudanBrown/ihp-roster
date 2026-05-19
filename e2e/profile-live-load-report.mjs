#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

if (process.argv.length < 4) {
    console.log('Usage: node e2e/profile-live-load-report.mjs <k6-metrics.ndjson> <output-dir> [metadata.json]');
    process.exit(64);
}

const metricsPath = path.resolve(process.argv[2]);
const outputDir = path.resolve(process.argv[3]);
const metadataPath = process.argv[4] ? path.resolve(process.argv[4]) : null;
const metadata = metadataPath && fs.existsSync(metadataPath) ? JSON.parse(fs.readFileSync(metadataPath, 'utf8')) : {};
const summary = summarize(metricsPath);
fs.mkdirSync(outputDir, { recursive: true });
fs.writeFileSync(path.join(outputDir, 'live-profile.json'), JSON.stringify({ metadata, summary }, null, 2));
fs.writeFileSync(path.join(outputDir, 'live-profile.md'), renderMarkdown(metadata, summary));
console.log(`Live profile summary: ${path.join(outputDir, 'live-profile.md')}`);

function summarize(filePath) {
    const counters = new Map();
    const trends = new Map();
    const checks = { total: 0, failed: 0 };
    const httpStatuses = new Map();

    const content = fs.readFileSync(filePath, 'utf8');
    for (const line of content.split('\n')) {
        if (!line.trim()) continue;
        const event = JSON.parse(line);
        if (event.type !== 'Point') continue;
        const data = event.data || {};
        const value = Number(data.value);
        if (!Number.isFinite(value)) continue;

        if (event.metric === 'checks') {
            checks.total += 1;
            if (value === 0) checks.failed += 1;
        } else if (event.metric.startsWith('profile_live_')) {
            if (event.metric.endsWith('_duration') || event.metric.endsWith('_latency')) {
                if (!trends.has(event.metric)) trends.set(event.metric, []);
                trends.get(event.metric).push(value);
            } else {
                counters.set(event.metric, (counters.get(event.metric) || 0) + value);
            }
        } else if (event.metric === 'http_req_duration') {
            const tags = data.tags || {};
            const route = tags.route || 'unknown';
            const status = String(tags.status || 'unknown');
            const key = `${route}:${status}`;
            httpStatuses.set(key, (httpStatuses.get(key) || 0) + 1);
        }
    }

    return {
        counters: Object.fromEntries([...counters.entries()].sort()),
        trends: Object.fromEntries([...trends.entries()].sort().map(([name, values]) => [name, trendSummary(values)])),
        checks,
        httpStatuses: Object.fromEntries([...httpStatuses.entries()].sort()),
    };
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

function round(value) {
    return Math.round(value * 10) / 10;
}

function renderMarkdown(metadata, summary) {
    const rows = [
        '# Live Load Profile',
        '',
        `Subscribers: \`${metadata.subscribers ?? ''}\``,
        `Mutators: \`${metadata.mutators ?? ''}\``,
        `Database: \`${metadata.database ?? ''}\``,
        '',
        '## Counters',
        '',
        '| Metric | Count |',
        '| --- | ---: |',
        ...Object.entries(summary.counters).map(([name, value]) => `| \`${name}\` | ${value} |`),
        '',
        '## Trends',
        '',
        '| Metric | Count | Median | P95 | P99 | Max |',
        '| --- | ---: | ---: | ---: | ---: | ---: |',
        ...Object.entries(summary.trends).map(([name, value]) => `| \`${name}\` | ${value.count} | ${value.medianMs} | ${value.p95Ms} | ${value.p99Ms} | ${value.maxMs} |`),
        '',
        '## Checks',
        '',
        `Failed checks: \`${summary.checks.failed}/${summary.checks.total}\``,
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
