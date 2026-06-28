#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { chromium } from 'playwright';

const DEFAULT_BASE_URL = process.env.OTEL_BROWSER_BASE_URL || process.env.APP_BASE_URL || 'http://127.0.0.1:8000';
const DEFAULT_CATALOG = process.env.PROFILE_SCENARIO_CATALOG || 'e2e/profile-scenarios.json';
const DEFAULT_OUTPUT_DIR = process.env.OTEL_BROWSER_OUTPUT_DIR || `output/otel-browser/${new Date().toISOString().replace(/[:.]/g, '-')}`;
const DEFAULT_MANIFEST = process.env.PROFILE_SEED_MANIFEST || 'build/profile-seed/latest/manifest.json';
const DEFAULT_ROLE = process.env.OTEL_BROWSER_ROLE || 'manager';
const ROLE_DEFAULTS = {
    manager: { email: 'dev-manager@example.com', password: 'password123' },
    admin: { email: 'venue2@bepis.lol', password: 'venue2' },
    owner: { email: 'owner@bepis.lol', password: 'owner' },
    worker: { email: 'dev-worker@example.com', password: 'password123' },
    support: { email: 'admin@bepis.lol', password: 'admin' },
};

const DEFAULT_ROUTES = {
    rosterCurrent: '/ShowRosterWeek?weekOffset=0',
    rosterHistorical: '/ShowRosterWeek?weekOffset=-8',
    rosterFuture: '/ShowRosterWeek?weekOffset=8',
    rosterContentFragment: '/ShowRosterWeekContentFragment?weekOffset=0',
    rosterStaffPanelFragment: '/ShowRosterWeekStaffPanelFragment?weekOffset=0',
    rosterOverviewFragment: '/ShowRosterWeekOverviewFragment?weekOffset=0',
    timesheetsCurrent: '/ShowTimesheetWeek?weekOffset=0',
    timesheetsReset: '/Timesheets?showApproved=true&showAllStaff=true',
    timesheetsStaffFilter: '/ShowTimesheetWeek?weekOffset=0&showApproved=true&showAllStaff=true',
    timesheetDayFragment: '/ShowTimesheetDayColumnsFragment?weekOffset=0',
    leaveRequests: '/LeaveRequests',
    leaveRequestsFragment: '/ShowLeaveRequestsContentFragment',
    profileLeave: '/EditProfile?section=leave',
    profileLeaveRequestsFragment: '/ShowProfileLeaveRequestsContentFragment',
    xero: '/Xero',
    adminXeroFragment: '/ShowAdminXeroFragment',
    admin: '/Admin',
    adminExports: '/Admin#exports',
    adminExportsFragment: '/ShowAdminExportsFragment',
    adminInvitesFragment: '/ShowAdminInvitesFragment',
    adminShiftTypesFragment: '/ShowAdminShiftTypesFragment',
    adminRosterGroupsFragment: '/ShowAdminRosterGroupsFragment',
    adminExportsFragment: '/ShowAdminExportsFragment',
    adminVenueSettingsFragment: '/ShowAdminVenueSettingsFragment',
    editProfile: '/EditProfile',
    profileSecurity: '/EditProfile?section=security',
    profileRsa: '/EditProfile?section=rsa',
};

function usage() {
    console.log(`Usage:
  node e2e/otel-browser.mjs [options]

Options:
  --base-url <url>       Running app URL (default: ${DEFAULT_BASE_URL})
  --scenario <name>      Browser/load scenario name, or full (default: full)
  --catalog <path>       Scenario catalog (default: ${DEFAULT_CATALOG})
  --manifest <path>      Optional profile seed manifest (default: ${DEFAULT_MANIFEST})
  --output-dir <path>    Artifact directory (default: ${DEFAULT_OUTPUT_DIR})
  --run-id <id>          Diagnostic trace run id (default: random UUID)
  --role <role>          manager|admin|owner|worker|support (default: ${DEFAULT_ROLE})
  --email <email>        Override login email
  --password <password>  Override login password
  --timeout-ms <ms>      Navigation/selector timeout (default: 60000)
  --headed               Run Chromium headed
  --help                 Show this message
`);
}

function parseArgs(argv) {
    const roleDefaults = ROLE_DEFAULTS[DEFAULT_ROLE] || ROLE_DEFAULTS.manager;
    const options = {
        baseUrl: DEFAULT_BASE_URL,
        scenario: process.env.OTEL_BROWSER_SCENARIO || 'full',
        catalogPath: DEFAULT_CATALOG,
        manifestPath: DEFAULT_MANIFEST,
        outputDir: DEFAULT_OUTPUT_DIR,
        runId: process.env.OTEL_TRACE_RUN_ID || randomUUID(),
        role: DEFAULT_ROLE,
        email: process.env.OTEL_BROWSER_EMAIL || roleDefaults.email,
        password: process.env.OTEL_BROWSER_PASSWORD || roleDefaults.password,
        timeoutMs: Number(process.env.OTEL_BROWSER_TIMEOUT_MS || '60000'),
        headed: false,
    };
    const args = [...argv];
    if (args.includes('--help')) {
        usage();
        process.exit(0);
    }
    while (args.length > 0) {
        const arg = args.shift();
        const [flag, inlineValue] = arg.includes('=') ? arg.split(/=(.*)/s, 2) : [arg, null];
        const next = () => inlineValue ?? args.shift();
        switch (flag) {
            case '--base-url': options.baseUrl = next(); break;
            case '--scenario': options.scenario = next(); break;
            case '--catalog': options.catalogPath = next(); break;
            case '--manifest': options.manifestPath = next(); break;
            case '--output-dir': options.outputDir = next(); break;
            case '--run-id': options.runId = next(); break;
            case '--role': {
                options.role = next();
                const defaults = ROLE_DEFAULTS[options.role];
                if (defaults) {
                    if (!process.env.OTEL_BROWSER_EMAIL) options.email = defaults.email;
                    if (!process.env.OTEL_BROWSER_PASSWORD) options.password = defaults.password;
                }
                break;
            }
            case '--email': options.email = next(); break;
            case '--password': options.password = next(); break;
            case '--timeout-ms': options.timeoutMs = Number(next()); break;
            case '--headed': options.headed = true; break;
            default: throw new Error(`Unknown argument: ${arg}`);
        }
    }
    return options;
}

function readJsonIfExists(file) {
    if (!file || !fs.existsSync(file)) return null;
    return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function absoluteUrl(baseUrl, target) {
    if (target.startsWith('http://') || target.startsWith('https://')) return target;
    return new URL(target.startsWith('/') ? target : `/${target}`, baseUrl).toString();
}

function scenarioEntries(catalog, manifest, scenarioName) {
    const routes = { ...DEFAULT_ROUTES, ...(manifest?.routes || {}) };
    const browserByName = new Map();
    for (const entries of Object.values(catalog.browserScenarios || {})) {
        for (const entry of entries) browserByName.set(entry.name, entry);
    }
    function normalize(entry) {
        if (entry.include) return expandLoadScenario(entry.include);
        const browserEntry = browserByName.get(entry.name) || entry;
        if (browserEntry.kind && browserEntry.kind !== 'visit') return [];
        const routeKey = entry.routeKey || browserEntry.routeKey;
        const target = routes[routeKey] || entry.fallbackPath || browserEntry.fallbackPath;
        if (!target) return [];
        return [{
            name: entry.name || browserEntry.name || routeKey,
            target,
            readySelector: entry.readySelector || browserEntry.readySelector || 'body',
        }];
    }
    function expandLoadScenario(name) {
        return (catalog.loadScenarios?.[name] || []).flatMap(normalize);
    }
    if (scenarioName === 'full') {
        return ['roster', 'timesheets', 'leave', 'profile', 'admin', 'xero'].flatMap((name) => (catalog.browserScenarios?.[name] || []).flatMap(normalize));
    }
    if (catalog.browserScenarios?.[scenarioName]) return catalog.browserScenarios[scenarioName].flatMap(normalize);
    if (catalog.loadScenarios?.[scenarioName]) return expandLoadScenario(scenarioName);
    throw new Error(`Unknown scenario: ${scenarioName}`);
}

async function gotoReady(page, options, target, selector, stepName) {
    await page.setExtraHTTPHeaders({
        'X-Bepis-Trace-Run': options.runId,
        'X-Bepis-Trace-Step': stepName,
    });
    const startedAt = performance.now();
    const response = await page.goto(absoluteUrl(options.baseUrl, target), { waitUntil: 'domcontentloaded', timeout: options.timeoutMs });
    if (selector) await page.locator(selector).first().waitFor({ state: 'visible', timeout: options.timeoutMs });
    await page.waitForLoadState('networkidle', { timeout: Math.min(options.timeoutMs, 10000) }).catch(() => null);
    return { durationMs: performance.now() - startedAt, status: response?.status() || null, finalUrl: page.url() };
}

async function dismissOptionalPasskeyPrompt(page) {
    const prompts = page.locator('.js-passkey-setup-prompt');
    await prompts.first().waitFor({ state: 'attached', timeout: 1000 }).catch(() => null);
    if ((await prompts.count()) === 0) return;
    await prompts.evaluateAll((elements) => {
        for (const element of elements) element.remove();
        document.body.classList.remove('modal-open');
        document.body.style.overflow = '';
    });
}

async function login(page, options) {
    const loginStep = 'auth.login_page';
    await gotoReady(page, options, '/NewSession', '#email', loginStep);
    await page.fill('#email', options.email);
    await page.fill('#password', options.password);
    await page.setExtraHTTPHeaders({
        'X-Bepis-Trace-Run': options.runId,
        'X-Bepis-Trace-Step': 'auth.create_session',
    });
    await page.locator('button[type="submit"]').first().click();
    await page.waitForURL((url) => !url.pathname.includes('/NewSession'), { timeout: options.timeoutMs }).catch(() => null);
    if (page.url().includes('/NewSession')) {
        const flashText = await page.locator('.alert').first().textContent({ timeout: 1000 }).catch(() => 'No flash message');
        throw new Error(`Login failed for ${options.email}: ${flashText.trim()}`);
    }
    await page.locator('body').waitFor({ state: 'visible', timeout: options.timeoutMs });
    await dismissOptionalPasskeyPrompt(page);
}

async function main() {
    const options = parseArgs(process.argv.slice(2));
    const catalog = readJsonIfExists(options.catalogPath);
    if (!catalog) throw new Error(`Missing scenario catalog: ${options.catalogPath}`);
    const manifest = readJsonIfExists(options.manifestPath);
    if (manifest?.accounts?.venueAdmin && options.role === 'admin' && !process.env.OTEL_BROWSER_EMAIL) {
        options.email = manifest.accounts.venueAdmin.email;
        options.password = manifest.accounts.venueAdmin.password;
    } else if (manifest?.accounts?.primaryManager && options.role === 'manager' && !process.env.OTEL_BROWSER_EMAIL) {
        options.email = manifest.accounts.primaryManager.email;
        options.password = manifest.accounts.primaryManager.password;
    }
    const entries = scenarioEntries(catalog, manifest, options.scenario);
    fs.mkdirSync(options.outputDir, { recursive: true });
    const journey = { runId: options.runId, scenario: options.scenario, role: options.role, email: options.email, baseUrl: options.baseUrl, startedAt: new Date().toISOString(), steps: [] };
    const browser = await chromium.launch({ headless: !options.headed });
    const page = await browser.newPage();
    try {
        await login(page, options);
        for (const entry of entries) {
            const record = { name: entry.name, target: entry.target, readySelector: entry.readySelector, ok: false };
            try {
                const result = await gotoReady(page, options, entry.target, entry.readySelector, entry.name);
                Object.assign(record, result, { ok: true });
                console.log(`${entry.name} ${result.status || '-'} ${result.durationMs.toFixed(1)}ms ${result.finalUrl}`);
            } catch (error) {
                record.error = String(error?.message || error);
                record.finalUrl = page.url();
                record.body = await page.locator('body').innerText({ timeout: 1000 }).catch(() => '');
                console.log(`FAILED ${entry.name}: ${record.error}`);
            }
            journey.steps.push(record);
            await dismissOptionalPasskeyPrompt(page).catch(() => null);
        }
    } finally {
        await browser.close();
        journey.completedAt = new Date().toISOString();
        fs.writeFileSync(path.join(options.outputDir, 'journey.json'), JSON.stringify(journey, null, 2));
        fs.writeFileSync(path.join(options.outputDir, 'run-id.txt'), `${options.runId}\n`);
    }
    const failures = journey.steps.filter((step) => !step.ok).length;
    console.log(`OTel browser run ${options.runId}: ${journey.steps.length - failures}/${journey.steps.length} steps ok`);
    console.log(`Artifacts: ${options.outputDir}`);
    if (failures) process.exitCode = 2;
}

await main();
