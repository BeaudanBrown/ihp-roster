#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { OTEL_ARTIFACT_SCHEMA } from './otel-artifact.mjs';

function usage() { console.log('Usage: node e2e/profile-compare.mjs <before-summary.json> <after-summary.json> [output.md]'); }
function read(file) { return JSON.parse(fs.readFileSync(path.resolve(file), 'utf8')); }
const round = (value) => Math.round(value * 10) / 10;
function delta(before, after) { const value = round(after - before); return { value, percent: before === 0 ? null : round(value / before * 100) }; }
function format(change, suffix = '') { const percent = change.percent === null ? '' : ` (${change.percent >= 0 ? '+' : ''}${change.percent}%)`; return `${change.value >= 0 ? '+' : ''}${change.value}${suffix}${percent}`; }
function key(row) { return `${row.scenario || ''}\u0000${row.method || ''}\u0000${row.route || ''}\u0000${row.action || ''}\u0000${row.span || ''}`; }
function routeKey(row) { return `${row.scenario || ''}\u0000${row.method || ''}\u0000${row.route || ''}\u0000${row.action || ''}`; }
function mapBy(rows, keyFn) { return new Map((rows || []).map((row) => [keyFn(row), row])); }
function stat(row, name, fallback) { return Number(row?.[name] ?? row?.[fallback] ?? 0); }
function pressure(profile) {
    const value = profile.loadPressure || profile.context?.loadPressure || profile.context?.summary?.k6 || profile.context?.summary || {};
    return { droppedIterations: Number(value.droppedIterations || value.dropped_iterations || 0), vuSaturation: Number(value.vuSaturation || value.vu_saturation || 0), iterations: Number(value.iterations || value.iterationCount || 0), vus: Number(value.vus || value.maxVUs || 0) };
}
function normalize(profile) {
    if (profile.schemaVersion === OTEL_ARTIFACT_SCHEMA) return profile;
    if (profile.schemaVersion === 'bepis.otel.suite.v2' || Array.isArray(profile.scenarios)) {
        const scenarios = profile.scenarios.map((entry) => ({ scenario: entry.scenario, report: normalize(entry.report || entry) }));
        return {
            schemaVersion: profile.schemaVersion || 'legacy-suite', context: { suiteDir: profile.suiteDir || null },
            summary: { statuses: scenarios.reduce((result, entry) => { const status = entry.report.summary?.statuses || {}; result.ok += status.ok || 0; result.ihpResponseExit += status.ihpResponseExit || 0; result.error += status.error || 0; return result; }, { ok: 0, ihpResponseExit: 0, error: 0 }) },
            spanGroups: scenarios.flatMap((entry) => (entry.report.spanGroups || []).map((row) => ({ scenario: entry.scenario, ...row }))),
            routes: scenarios.flatMap((entry) => (entry.report.routes || []).map((row) => ({ scenario: entry.scenario, ...row }))),
            loadPressure: scenarios.reduce((result, entry) => { const value = pressure(entry.report); result.droppedIterations += value.droppedIterations; result.iterations += value.iterations; result.vuSaturation = Math.max(result.vuSaturation, value.vuSaturation); result.vus = Math.max(result.vus, value.vus); return result; }, { droppedIterations: 0, iterations: 0, vuSaturation: 0, vus: 0 }),
        };
    }
    const summary = profile.summary || {};
    return {
        schemaVersion: 'legacy', context: profile.metadata || null,
        summary: { traceCount: summary.traceCount || 0, spanCount: summary.spanCount || 0, statuses: summary.statuses || { ok: 0, ihpResponseExit: 0, error: 0 } },
        spanGroups: (summary.spans || profile.slowestSpans || []).map((row) => ({ method: row.method || '', route: row.route || row.path || '', action: row.action || '', span: row.span || row.name, durationMs: { sampleCount: row.count || row.sampleCount || 1, median: row.medianMs ?? row.durationMs ?? 0, p95: row.p95Ms ?? row.durationMs ?? 0 }, exclusiveMs: { sampleCount: row.count || 1, median: row.exclusiveMedianMs || 0, p95: row.exclusiveP95Ms || 0 } })),
        routes: (summary.http || []).map((row) => ({ method: row.method || '', route: row.route || row.path || '', action: row.action || '', durationMs: { sampleCount: row.count || row.sampleCount || 1, median: row.medianMs ?? row.totalMs ?? 0, p95: row.p95Ms ?? row.totalMs ?? 0 } })),
        loadPressure: summary,
    };
}
export function compareOtelProfiles(beforeValue, afterValue) {
    const before = normalize(beforeValue); const after = normalize(afterValue);
    const beforeSpans = mapBy(before.spanGroups, key); const beforeRoutes = mapBy(before.routes, routeKey);
    const spans = (after.spanGroups || []).filter((row) => beforeSpans.has(key(row))).map((afterRow) => {
        const beforeRow = beforeSpans.get(key(afterRow)); const beforeCount = stat(beforeRow.durationMs, 'sampleCount'); const afterCount = stat(afterRow.durationMs, 'sampleCount');
        return { identity: { scenario: afterRow.scenario || '', method: afterRow.method || '', route: afterRow.route || '', action: afterRow.action || '', span: afterRow.span }, beforeSamples: beforeCount, afterSamples: afterCount, confidence: Math.min(beforeCount, afterCount) >= 20 ? 'high' : Math.min(beforeCount, afterCount) >= 5 ? 'medium' : 'low', p95Ms: delta(stat(beforeRow.durationMs, 'p95', 'p95Ms'), stat(afterRow.durationMs, 'p95', 'p95Ms')), medianMs: delta(stat(beforeRow.durationMs, 'median', 'medianMs'), stat(afterRow.durationMs, 'median', 'medianMs')), exclusiveP95Ms: delta(stat(beforeRow.exclusiveMs, 'p95', 'p95Ms'), stat(afterRow.exclusiveMs, 'p95', 'p95Ms')) };
    }).sort((a, b) => Math.abs(b.p95Ms.value) - Math.abs(a.p95Ms.value));
    const routes = (after.routes || []).filter((row) => beforeRoutes.has(routeKey(row))).map((afterRow) => {
        const beforeRow = beforeRoutes.get(routeKey(afterRow)); return { identity: { scenario: afterRow.scenario || '', method: afterRow.method || '', route: afterRow.route || '', action: afterRow.action || '' }, beforeSamples: stat(beforeRow.durationMs, 'sampleCount'), afterSamples: stat(afterRow.durationMs, 'sampleCount'), p95Ms: delta(stat(beforeRow.durationMs, 'p95'), stat(afterRow.durationMs, 'p95')), medianMs: delta(stat(beforeRow.durationMs, 'median'), stat(afterRow.durationMs, 'median')) };
    }).sort((a, b) => Math.abs(b.p95Ms.value) - Math.abs(a.p95Ms.value));
    const beforePressure = pressure(before); const afterPressure = pressure(after);
    return { schemaVersion: 'bepis.otel.comparison.v2', context: { beforeSchema: before.schemaVersion, afterSchema: after.schemaVersion, before: before.context, after: after.context, matchedSpanGroups: spans.length, matchedRoutes: routes.length, note: 'Confidence is based on the smaller matched sample count; deltas are descriptive, not statistical significance tests.' }, spans, routes, loadPressure: { before: beforePressure, after: afterPressure, droppedIterations: delta(beforePressure.droppedIterations, afterPressure.droppedIterations), vuSaturation: delta(beforePressure.vuSaturation, afterPressure.vuSaturation) }, failures: { before: before.summary?.statuses || {}, after: after.summary?.statuses || {} } };
}
export function renderComparison(beforePath, afterPath, comparison) {
    return `${['# OpenTelemetry Profile Comparison', '', `Before: \`${beforePath}\``, `After: \`${afterPath}\``, `Matched span groups: ${comparison.context.matchedSpanGroups}; matched routes: ${comparison.context.matchedRoutes}.`, comparison.context.note, '', '## Matched Span Deltas', '', '| Route/action | Span | Samples B/A | Confidence | P95 delta | Median delta | Exclusive P95 delta |', '| --- | --- | ---: | --- | ---: | ---: | ---: |', ...comparison.spans.slice(0, 50).map((row) => `| \`${[row.identity.scenario, row.identity.route || row.identity.action].filter(Boolean).join(':')}\` | \`${row.identity.span}\` | ${row.beforeSamples}/${row.afterSamples} | ${row.confidence} | ${format(row.p95Ms, 'ms')} | ${format(row.medianMs, 'ms')} | ${format(row.exclusiveP95Ms, 'ms')} |`), '', '## Matched Route Deltas', '', '| Route/action | Samples B/A | P95 delta | Median delta |', '| --- | ---: | ---: | ---: |', ...comparison.routes.slice(0, 30).map((row) => `| \`${[row.identity.scenario, row.identity.route || row.identity.action].filter(Boolean).join(':')}\` | ${row.beforeSamples}/${row.afterSamples} | ${format(row.p95Ms, 'ms')} | ${format(row.medianMs, 'ms')} |`), '', '## Load Pressure', '', `Dropped iterations: ${comparison.loadPressure.before.droppedIterations} → ${comparison.loadPressure.after.droppedIterations} (${format(comparison.loadPressure.droppedIterations)})`, `VU saturation: ${comparison.loadPressure.before.vuSaturation} → ${comparison.loadPressure.after.vuSaturation} (${format(comparison.loadPressure.vuSaturation)})`, '', '## Failure Classification', '', `Before: ${comparison.failures.before.error || 0} real failures, ${comparison.failures.before.ihpResponseExit || 0} IHP response exits.`, `After: ${comparison.failures.after.error || 0} real failures, ${comparison.failures.after.ihpResponseExit || 0} IHP response exits.`, ''].join('\n')}\n`;
}
function main() {
    const [beforePath, afterPath, outputPath] = process.argv.slice(2); if (!beforePath || !afterPath) { usage(); process.exit(1); }
    const comparison = compareOtelProfiles(read(beforePath), read(afterPath)); const markdown = renderComparison(beforePath, afterPath, comparison);
    if (!outputPath) process.stdout.write(markdown); else { const output = path.resolve(outputPath); fs.mkdirSync(path.dirname(output), { recursive: true }); fs.writeFileSync(output, markdown); fs.writeFileSync(output.replace(/\.md$/i, '') + '.json', `${JSON.stringify(comparison, null, 2)}\n`); console.log(`Profile comparison: ${output}`); }
}
if (import.meta.url === `file://${process.argv[1]}`) main();
