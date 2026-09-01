#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { performance } from 'node:perf_hooks';
import { chromium } from 'playwright';

const DEFAULT_BASE_URL = process.env.PROFILE_BASE_URL || process.env.E2E_BASE_URL || 'http://127.0.0.1:8000';
const DEFAULT_OUTPUT_DIR = process.env.PROFILE_OUTPUT_DIR || 'output/profile/manual';
const DEFAULT_MANIFEST = process.env.PROFILE_SEED_MANIFEST || 'build/profile-seed/latest/manifest.json';
const DEFAULT_SCENARIO_CATALOG = process.env.PROFILE_SCENARIO_CATALOG || 'e2e/profile-scenarios.json';
const DEFAULT_RUNS = Number(process.env.PROFILE_RUNS || '5');
const DEFAULT_WARMUP_RUNS = Number(process.env.PROFILE_WARMUP_RUNS || '1');
const DEFAULT_TIMEOUT_MS = Number(process.env.PROFILE_TIMEOUT_MS || '120000');

function printUsage() {
    console.log(`Usage:
  node e2e/profile-app.mjs [options]

Options:
  --base-url <url>       Running app URL (default: ${DEFAULT_BASE_URL})
  --output-dir <path>    Artifact directory (default: ${DEFAULT_OUTPUT_DIR})
  --manifest <path>      Profile seed manifest (default: ${DEFAULT_MANIFEST})
  --scenario <name>      full|roster|timesheets|leave|xero|admin|profile|writes (default: full)
  --scenario-catalog <path>
                         Shared scenario catalog (default: ${DEFAULT_SCENARIO_CATALOG})
  --runs <n>             Measured iterations per scenario (default: ${DEFAULT_RUNS})
  --warmup-runs <n>      Warmup iterations per scenario (default: ${DEFAULT_WARMUP_RUNS})
  --email <email>        Override manifest login email
  --password <password>  Override manifest login password
  --timeout-ms <ms>      Navigation/selector timeout (default: ${DEFAULT_TIMEOUT_MS})
  --headed               Run Chromium headed
  --help                 Show this message
`);
}

function parseArgs(argv) {
    const args = [...argv];
    if (args.includes('--help')) {
        printUsage();
        process.exit(0);
    }

    const options = {
        baseUrl: DEFAULT_BASE_URL,
        outputDir: DEFAULT_OUTPUT_DIR,
        manifestPath: DEFAULT_MANIFEST,
        scenarioCatalogPath: DEFAULT_SCENARIO_CATALOG,
        scenario: 'full',
        runs: DEFAULT_RUNS,
        warmupRuns: DEFAULT_WARMUP_RUNS,
        email: null,
        password: null,
        timeoutMs: DEFAULT_TIMEOUT_MS,
        headed: false,
    };

    while (args.length > 0) {
        const arg = args.shift();
        const [flag, inlineValue] = arg.includes('=') ? arg.split(/=(.*)/s, 2) : [arg, null];
        const nextValue = () => inlineValue ?? args.shift();
        switch (flag) {
            case '--base-url':
                options.baseUrl = nextValue();
                break;
            case '--output-dir':
                options.outputDir = nextValue();
                break;
            case '--manifest':
                options.manifestPath = nextValue();
                break;
            case '--scenario-catalog':
                options.scenarioCatalogPath = nextValue();
                break;
            case '--scenario':
                options.scenario = nextValue();
                break;
            case '--runs':
                options.runs = Number(nextValue() || '0');
                break;
            case '--warmup-runs':
                options.warmupRuns = Number(nextValue() || '0');
                break;
            case '--email':
                options.email = nextValue();
                break;
            case '--password':
                options.password = nextValue();
                break;
            case '--timeout-ms':
                options.timeoutMs = Number(nextValue() || '0');
                break;
            case '--headed':
                options.headed = true;
                break;
            default:
                throw new Error(`Unknown argument: ${arg}`);
        }
    }

    if (!options.baseUrl) throw new Error('--base-url is required');
    if (!options.outputDir) throw new Error('--output-dir is required');
    if (!options.manifestPath) throw new Error('--manifest is required');
    if (!['full', 'roster', 'timesheets', 'leave', 'xero', 'admin', 'profile', 'writes'].includes(options.scenario)) {
        throw new Error(`Unsupported --scenario: ${options.scenario}`);
    }
    if (!Number.isFinite(options.runs) || options.runs < 1) throw new Error('--runs must be a positive number');
    if (!Number.isFinite(options.warmupRuns) || options.warmupRuns < 0) throw new Error('--warmup-runs must be zero or greater');
    if (!Number.isFinite(options.timeoutMs) || options.timeoutMs <= 0) throw new Error('--timeout-ms must be a positive number');

    return options;
}

function readManifest(manifestPath) {
    const resolvedPath = path.resolve(manifestPath);
    return JSON.parse(fs.readFileSync(resolvedPath, 'utf8'));
}

function readScenarioCatalog(catalogPath) {
    return JSON.parse(fs.readFileSync(path.resolve(catalogPath), 'utf8'));
}

function absoluteUrl(baseUrl, target) {
    if (target.startsWith('http://') || target.startsWith('https://')) return target;
    return new URL(target.startsWith('/') ? target : `/${target}`, baseUrl).toString();
}

async function gotoReady(page, baseUrl, target, selector, timeoutMs) {
    const startedAt = performance.now();
    const url = absoluteUrl(baseUrl, target);
    try {
        await page.goto(url, { waitUntil: 'domcontentloaded', timeout: timeoutMs });
    } catch (error) {
        if (!String(error?.message || '').includes('net::ERR_ABORTED')) throw error;
        await page.waitForTimeout(250);
        await page.goto(url, { waitUntil: 'domcontentloaded', timeout: timeoutMs });
    }
    if (selector) {
        try {
            await page.locator(selector).first().waitFor({ state: 'visible', timeout: timeoutMs });
        } catch (error) {
            const bodyText = await page.locator('body').innerText({ timeout: 1000 }).catch(() => '');
            throw new Error(`Timed out waiting for ${selector} after navigating to ${target}; current URL: ${page.url()}; body: ${bodyText.slice(0, 500)}`, { cause: error });
        }
    }
    await page.waitForLoadState('networkidle', { timeout: Math.min(timeoutMs, 10000) }).catch(() => null);
    return performance.now() - startedAt;
}

async function login(page, options, account) {
    await gotoReady(page, options.baseUrl, '/NewSession', '#email', options.timeoutMs);
    await page.fill('#email', options.email || account.email);
    await page.fill('#password', options.password || account.password);
    await page.locator('button[type="submit"]').first().click();
    await page.waitForURL((url) => !url.pathname.includes('/NewSession'), { timeout: options.timeoutMs }).catch(() => null);
    if (page.url().includes('/NewSession')) {
        const flashText = (await page.locator('.alert').first().textContent().catch(() => null)) || 'No flash message';
        throw new Error(`Profile login failed: ${flashText.trim()}`);
    }
    await page.locator('.app-shell').first().waitFor({ state: 'visible', timeout: options.timeoutMs });
}

async function enableVirtualPasskeyAuthenticator(page) {
    const cdp = await page.context().newCDPSession(page);
    await cdp.send('WebAuthn.enable');
    const { authenticatorId } = await cdp.send('WebAuthn.addVirtualAuthenticator', {
        options: {
            protocol: 'ctap2',
            transport: 'internal',
            hasResidentKey: true,
            hasUserVerification: true,
            isUserVerified: true,
            automaticPresenceSimulation: true,
        },
    });
    await cdp.send('WebAuthn.setAutomaticPresenceSimulation', {
        authenticatorId,
        enabled: true,
    });
    return { cdp, authenticatorId };
}

async function ensurePrivilegedPasskeyReady(page, options) {
    if (!page.url().includes('/EditProfile')) return;
    await page.locator('#profile-content-fragment').waitFor({ state: 'visible', timeout: options.timeoutMs });
    const securityToggle = page.getByRole('button', { name: 'Sign-In Methods' });
    if ((await securityToggle.getAttribute('aria-expanded')) !== 'true') {
        await securityToggle.click();
    }
    const addButton = page.getByRole('button', { name: 'Add passkey' });
    await addButton.waitFor({ state: 'visible', timeout: options.timeoutMs });
    const finishRegistration = page.waitForResponse((response) =>
        response.request().method() === 'POST'
        && new URL(response.url()).pathname.includes('FinishPasskeyRegistration')
        && response.status() >= 200
        && response.status() < 300
    );
    await addButton.click();
    await finishRegistration;
}

function scenarioDefinitions(manifest, catalog) {
    const routes = manifest.routes || {};
    return Object.fromEntries(Object.entries(catalog.browserScenarios || {}).map(([scenarioName, entries]) => [
        scenarioName,
        entries.map((entry) => {
            if (entry.kind === 'exportGeneration') return { kind: 'exportGeneration', name: entry.name };
            return {
                kind: 'visit',
                name: entry.name,
                target: routes[entry.routeKey] || entry.fallbackPath,
                readySelector: entry.readySelector,
            };
        }),
    ]));
}

function selectedScenarios(options, manifest, catalog) {
    const definitions = scenarioDefinitions(manifest, catalog);
    const names = options.scenario === 'full' ? ['roster', 'timesheets', 'leave', 'profile'] : [options.scenario];
    return names.flatMap((name) => definitions[name]);
}

function accountForScenario(options, manifest) {
    if (options.email || options.password) return manifest.accounts?.primaryManager;
    if (['xero', 'admin', 'writes'].includes(options.scenario)) return manifest.accounts?.venueAdmin;
    return manifest.accounts?.primaryManager;
}

function parseProfileCounters(header) {
    if (!header) return [];
    return splitHeader(header).map((item) => {
        const [name, value] = item.split('=');
        return { name: name || '', value: Number(value) };
    }).filter((counter) => counter.name && Number.isFinite(counter.value));
}

function parseServerTiming(header) {
    return splitHeader(header).map((metric) => {
        const parts = metric.split(';').map((part) => part.trim()).filter(Boolean);
        const name = parts.shift() || '';
        const item = { name, durationMs: null, description: null, raw: metric };
        for (const part of parts) {
            const [key, ...valueParts] = part.split('=');
            const value = valueParts.join('=');
            if (key === 'dur') item.durationMs = Number(value);
            if (key === 'desc') item.description = unquote(value);
        }
        return item;
    });
}

function splitHeader(header) {
    const parts = [];
    let current = '';
    let inQuote = false;
    for (const char of header) {
        if (char === '"') inQuote = !inQuote;
        if (char === ',' && !inQuote) {
            parts.push(current.trim());
            current = '';
        } else {
            current += char;
        }
    }
    if (current.trim()) parts.push(current.trim());
    return parts;
}

function unquote(value) {
    if (!value) return value;
    return value.startsWith('"') && value.endsWith('"') ? value.slice(1, -1) : value;
}

function summarize(records) {
    const measured = records.filter((record) => !record.warmup);
    const requests = measured
        .filter((record) => record.serverTiming.length > 0)
        .map((record) => {
            const total = record.serverTiming.find((metric) => metric.name === 'app_total');
            const namedTotalMs = record.serverTiming
                .filter((metric) => metric.name !== 'app_total' && metric.durationMs !== null)
                .reduce((sum, metric) => sum + metric.durationMs, 0);
            const totalMs = total?.durationMs ?? record.wallMs;
            return { ...record, totalMs, namedTotalMs, unattributedMs: Math.max(0, totalMs - namedTotalMs) };
        });
    const spanGroups = new Map();
    const counterGroups = new Map();
    for (const record of measured) {
        for (const counter of record.profileCounters || []) {
            const key = `${record.scenario}::${new URL(record.url).pathname}::${counter.name}`;
            const group = counterGroups.get(key) || {
                scenario: record.scenario,
                path: new URL(record.url).pathname + new URL(record.url).search,
                counter: counter.name,
                total: 0,
                samples: [],
            };
            group.total += counter.value;
            group.samples.push(counter.value);
            counterGroups.set(key, group);
        }
    }
    for (const record of requests) {
        for (const metric of record.serverTiming) {
            if (metric.name === 'app_total' || metric.durationMs === null) continue;
            const key = `${record.scenario}::${metric.name}`;
            const group = spanGroups.get(key) || {
                scenario: record.scenario,
                span: metric.name,
                count: 0,
                samples: [],
                descriptions: new Set(),
            };
            group.count += 1;
            group.samples.push(metric.durationMs);
            if (metric.description) group.descriptions.add(metric.description);
            spanGroups.set(key, group);
        }
    }
    const missingServerTiming = summarizeMissingServerTiming(measured);

    return {
        requestCount: requests.length,
        missingServerTiming,
        slowestAttributionGaps: [...requests]
            .sort((a, b) => b.unattributedMs - a.unattributedMs)
            .slice(0, 20)
            .map((record) => ({
                scenario: record.scenario,
                method: record.method,
                path: new URL(record.url).pathname + new URL(record.url).search,
                status: record.status,
                totalMs: round(record.totalMs),
                namedTotalMs: round(record.namedTotalMs),
                unattributedMs: round(record.unattributedMs),
            })),
        counters: [...counterGroups.values()]
            .map((group) => ({
                scenario: group.scenario,
                path: group.path,
                counter: group.counter,
                total: group.total,
                count: group.samples.length,
                medianCount: round(percentile(group.samples, 0.5)),
                p95Count: round(percentile(group.samples, 0.95)),
                maxCount: round(Math.max(...group.samples)),
            }))
            .sort((a, b) => b.p95Count - a.p95Count || b.total - a.total)
            .slice(0, 50),
        largestResponses: measured
            .filter((record) => Number.isFinite(record.responseBytes))
            .sort((a, b) => b.responseBytes - a.responseBytes)
            .slice(0, 20)
            .map((record) => ({
                scenario: record.scenario,
                method: record.method,
                path: new URL(record.url).pathname + new URL(record.url).search,
                status: record.status,
                responseBytes: record.responseBytes,
            })),
        slowestRequests: requests
            .sort((a, b) => b.totalMs - a.totalMs)
            .slice(0, 20)
            .map((record) => ({
                scenario: record.scenario,
                method: record.method,
                path: new URL(record.url).pathname + new URL(record.url).search,
                status: record.status,
                totalMs: round(record.totalMs),
                wallMs: round(record.wallMs),
                unattributedMs: round(record.unattributedMs),
                responseBytes: record.responseBytes ?? null,
            })),
        slowestSpans: [...spanGroups.values()]
            .map((group) => ({
                scenario: group.scenario,
                span: group.span,
                count: group.count,
                medianMs: round(percentile(group.samples, 0.5)),
                p95Ms: round(percentile(group.samples, 0.95)),
                maxMs: round(Math.max(...group.samples)),
                descriptions: [...group.descriptions].slice(0, 5),
            }))
            .sort((a, b) => b.p95Ms - a.p95Ms)
            .slice(0, 30),
    };
}

function summarizeMissingServerTiming(records) {
    const groups = new Map();
    for (const record of records) {
        if (record.serverTiming.length > 0) continue;
        const url = new URL(record.url);
        if (isStaticProfilingNoise(url.pathname)) continue;
        const key = `${record.scenario}::${record.method}::${url.pathname}${url.search}`;
        const group = groups.get(key) || {
            scenario: record.scenario,
            method: record.method,
            path: url.pathname + url.search,
            count: 0,
            statuses: new Map(),
        };
        group.count += 1;
        group.statuses.set(record.status, (group.statuses.get(record.status) || 0) + 1);
        groups.set(key, group);
    }

    return [...groups.values()]
        .map((group) => ({
            scenario: group.scenario,
            method: group.method,
            path: group.path,
            count: group.count,
            statuses: Object.fromEntries(group.statuses),
        }))
        .sort((a, b) => b.count - a.count || a.path.localeCompare(b.path))
        .slice(0, 30);
}

function isStaticProfilingNoise(pathname) {
    return pathname.startsWith('/static/')
        || pathname.startsWith('/vendor/')
        || pathname === '/favicon.ico';
}

function percentile(values, p) {
    if (values.length === 0) return 0;
    const sorted = [...values].sort((a, b) => a - b);
    const index = Math.min(sorted.length - 1, Math.max(0, Math.ceil(sorted.length * p) - 1));
    return sorted[index];
}

function round(value) {
    return Math.round(value * 10) / 10;
}

function responseBytesFromHeaders(headers) {
    const profiledValue = Number(headers['x-profile-response-bytes']);
    if (Number.isFinite(profiledValue) && profiledValue >= 0) return profiledValue;
    const value = Number(headers['content-length']);
    return Number.isFinite(value) && value >= 0 ? value : null;
}

function formatBytes(bytes) {
    if (!Number.isFinite(bytes)) return '?';
    if (bytes >= 1024 * 1024) return `${round(bytes / (1024 * 1024))} MiB`;
    if (bytes >= 1024) return `${round(bytes / 1024)} KiB`;
    return `${round(bytes)} B`;
}

function renderMarkdown(options, manifest, summary) {
    const lines = [
        '# Profile Report',
        '',
        `Scenario: ${options.scenario}`,
        `Runs: ${options.runs} measured, ${options.warmupRuns} warmup`,
        `Seed scenario: ${manifest.scenario}`,
        `Current Operational window: ${manifest.currentWindowStart}`,
        '',
        '## Timing Coverage Anomalies',
        '',
        ...(summary.missingServerTiming.length === 0
            ? ['No sampled app responses were missing `Server-Timing`.', '']
            : [
                '| Scenario | Method | Count | Statuses | Path |',
                '| --- | --- | ---: | --- | --- |',
                ...summary.missingServerTiming.map((request) =>
                    `| ${request.scenario} | ${request.method} | ${request.count} | \`${JSON.stringify(request.statuses)}\` | \`${request.path}\` |`
                ),
                '',
            ]),
        '## Slowest Requests',
        '',
        '| Scenario | Method | Status | Total ms | Wall ms | Unattributed ms | Bytes | Path |',
        '| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |',
        ...summary.slowestRequests.map((request) =>
            `| ${request.scenario} | ${request.method} | ${request.status} | ${request.totalMs} | ${request.wallMs} | ${request.unattributedMs} | ${formatBytes(request.responseBytes)} | \`${request.path}\` |`
        ),
        '',
        '## Largest Attribution Gaps',
        '',
        '| Scenario | Method | Status | Total ms | Named span ms | Unattributed ms | Path |',
        '| --- | --- | ---: | ---: | ---: | ---: | --- |',
        ...summary.slowestAttributionGaps.map((request) =>
            `| ${request.scenario} | ${request.method} | ${request.status} | ${request.totalMs} | ${request.namedTotalMs} | ${request.unattributedMs} | \`${request.path}\` |`
        ),
        '',
        '## Largest Responses',
        '',
        '| Scenario | Method | Status | Bytes | Path |',
        '| --- | --- | ---: | ---: | --- |',
        ...summary.largestResponses.map((request) =>
            `| ${request.scenario} | ${request.method} | ${request.status} | ${formatBytes(request.responseBytes)} | \`${request.path}\` |`
        ),
        '',
        '## Profile Counters',
        '',
        '| Scenario | Path | Counter | Samples | Total | Median/request | P95/request | Max/request |',
        '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |',
        ...summary.counters.map((counter) =>
            `| ${counter.scenario} | \`${counter.path}\` | \`${counter.counter}\` | ${counter.count} | ${counter.total} | ${counter.medianCount} | ${counter.p95Count} | ${counter.maxCount} |`
        ),
        '',
        '## Slowest Spans',
        '',
        '| Scenario | Span | Count | Median ms | P95 ms | Max ms | Detail |',
        '| --- | --- | ---: | ---: | ---: | ---: | --- |',
        ...summary.slowestSpans.map((span) =>
            `| ${span.scenario} | \`${span.span}\` | ${span.count} | ${span.medianMs} | ${span.p95Ms} | ${span.maxMs} | ${span.descriptions.join('<br>')} |`
        ),
        '',
    ];
    return `${lines.join('\n')}\n`;
}

async function runExportGenerationScenario(page, options, manifest, scenario, records, iteration, warmup) {
    const routes = manifest.routes || {};
    await gotoReady(page, options.baseUrl, routes.adminExports || routes.admin || '/Admin#exports', '#exports', options.timeoutMs);

    const startedAt = performance.now();
    const exportResponse = await Promise.all([
        page.waitForResponse((response) =>
            response.request().method() === 'POST'
            && new URL(response.url()).pathname.includes('CreateExportJob')
        ),
        page.locator('[data-payroll-workbook-configuration] button', { hasText: 'Download' }).first().click(),
    ]).then(([response]) => response);
    const wallMs = performance.now() - startedAt;
    const exportResponseHeaders = exportResponse.headers();
    const serverTimingHeader = exportResponseHeaders['server-timing'];

    records.push({
        scenario: scenario.name,
        iteration,
        warmup,
        url: absoluteUrl(options.baseUrl, '/CreateExportJob'),
        method: 'POST',
        status: exportResponse.status(),
        serverTiming: serverTimingHeader ? parseServerTiming(serverTimingHeader) : [],
        profileCounters: parseProfileCounters(exportResponseHeaders['x-profile-counters']),
        responseBytes: responseBytesFromHeaders(exportResponseHeaders),
        wallMs: round(wallMs),
    });
}

async function main() {
    const options = parseArgs(process.argv.slice(2));
    if (options.scenario === 'xero') {
        options.baseUrl = options.baseUrl.replace('127.0.0.1', 'localhost');
    }
    const manifest = readManifest(options.manifestPath);
    const scenarioCatalog = readScenarioCatalog(options.scenarioCatalogPath);
    const scenarios = selectedScenarios(options, manifest, scenarioCatalog);
    const account = accountForScenario(options, manifest);
    if (!account) throw new Error(`Profile seed manifest is missing a login account for scenario: ${options.scenario}`);

    const records = [];
    let activeScenario = null;
    let activeIteration = null;
    let activeWarmup = false;

    const browser = await chromium.launch({ headless: !options.headed });
    const context = await browser.newContext({ viewport: { width: 1900, height: 1200 } });
    const page = await context.newPage();
    if (options.scenario === 'xero') {
        await enableVirtualPasskeyAuthenticator(page);
    }

    page.on('response', async (response) => {
        const request = response.request();
        const url = response.url();
        if (!activeScenario) return;
        if (new URL(url).origin !== new URL(options.baseUrl).origin) return;
        const responseHeaders = response.headers();
        const serverTimingHeader = responseHeaders['server-timing'];
        records.push({
            scenario: activeScenario,
            iteration: activeIteration,
            warmup: activeWarmup,
            url,
            method: request.method(),
            status: response.status(),
            serverTiming: serverTimingHeader ? parseServerTiming(serverTimingHeader) : [],
            profileCounters: parseProfileCounters(responseHeaders['x-profile-counters']),
            responseBytes: responseBytesFromHeaders(responseHeaders),
            wallMs: 0,
        });
    });

    try {
        await login(page, options, account);
        if (['xero', 'admin', 'writes'].includes(options.scenario)) {
            await ensurePrivilegedPasskeyReady(page, options);
        }
        for (const scenario of scenarios) {
            if (!scenario.target && scenario.kind !== 'exportGeneration') continue;
            const totalIterations = options.warmupRuns + options.runs;
            for (let index = 0; index < totalIterations; index += 1) {
                activeScenario = scenario.name;
                activeIteration = index - options.warmupRuns + 1;
                activeWarmup = index < options.warmupRuns;
                if (scenario.kind === 'exportGeneration') {
                    await runExportGenerationScenario(page, options, manifest, scenario, records, activeIteration, activeWarmup);
                } else {
                    const wallMs = await gotoReady(page, options.baseUrl, scenario.target, scenario.readySelector, options.timeoutMs);
                    const lastRecord = [...records].reverse().find((record) =>
                        record.scenario === scenario.name
                        && record.iteration === activeIteration
                        && record.warmup === activeWarmup
                        && record.serverTiming.length > 0
                    );
                    if (lastRecord) lastRecord.wallMs = round(wallMs);
                }
            }
        }
    } finally {
        activeScenario = null;
        await browser.close();
    }

    const summary = summarize(records);
    const outputDir = path.resolve(options.outputDir);
    fs.mkdirSync(outputDir, { recursive: true });
    fs.writeFileSync(path.join(outputDir, 'profile.json'), JSON.stringify({ options, manifest, records, summary }, null, 2));
    fs.writeFileSync(path.join(outputDir, 'profile.md'), renderMarkdown(options, manifest, summary));

    console.log(`Profile records: ${summary.requestCount}`);
    console.log(`Profile JSON: ${path.join(outputDir, 'profile.json')}`);
    console.log(`Profile report: ${path.join(outputDir, 'profile.md')}`);
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
