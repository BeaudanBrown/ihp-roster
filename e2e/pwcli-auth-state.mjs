#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';

const DEFAULT_BASE_URL = process.env.PWCLI_BASE_URL || 'http://127.0.0.1:8000';
const DEFAULT_PASSWORD = process.env.PWCLI_AUTH_PASSWORD || 'password123';
const DEFAULT_LOGIN_PATH = process.env.PWCLI_AUTH_LOGIN_PATH || '/NewSession';
const DEFAULT_LOGIN_SELECTOR = process.env.PWCLI_AUTH_LOGIN_SELECTOR || '#email';
const DEFAULT_NAVIGATION_TIMEOUT_MS = Number(process.env.PWCLI_AUTH_NAVIGATION_TIMEOUT_MS || '120000');
const DEFAULT_SELECTOR_TIMEOUT_MS = Number(process.env.PWCLI_AUTH_SELECTOR_TIMEOUT_MS || '120000');
const DEFAULT_POST_LOGIN_URL_PATTERN = process.env.PWCLI_AUTH_POST_LOGIN_URL_PATTERN || '(Dashboard|RosterWeeks|EditProfile)';

const ROLE_CONFIGS = {
    admin: {
        email: 'venue2@bepis.lol',
        password: 'venue2',
        readySelector: '#roster-content',
        targetPath: '/RosterWeeks',
    },
    manager: {
        email: 'dev-manager@example.com',
        readySelector: '#roster-content',
        targetPath: '/RosterWeeks',
    },
    support: {
        email: 'admin@bepis.lol',
        password: 'admin',
        readySelector: '#support-venue-id',
        targetPath: '/Support',
    },
    worker: {
        email: 'dev-worker@example.com',
        readySelector: '#roster-content',
        targetPath: '/RosterWeeks',
    },
};

function printUsage() {
    console.log(`Usage:
  node e2e/pwcli-auth-state.mjs <manager|worker|admin|support> [output-file] [options]

Options:
  --base-url <url>      Base URL for the running dev app (default: ${DEFAULT_BASE_URL})
  --email <email>       Override the seeded login email for the chosen role
  --password <pass>     Password for the chosen user (default: ${DEFAULT_PASSWORD})
  --login-path <path>   Login page path (default: ${DEFAULT_LOGIN_PATH})
  --login-selector <css>
                        Selector that proves the login page is ready (default: ${DEFAULT_LOGIN_SELECTOR})
  --navigation-timeout-ms <ms>
                        Navigation timeout (default: ${DEFAULT_NAVIGATION_TIMEOUT_MS})
  --selector-timeout-ms <ms>
                        Selector timeout (default: ${DEFAULT_SELECTOR_TIMEOUT_MS})
  --post-login-url-pattern <pattern>
                        Regex fragment for the expected post-login destination (default: ${DEFAULT_POST_LOGIN_URL_PATTERN})
  --help                Show this message
`);
}

function parseArgs(argv) {
    const args = [...argv];
    if (args.length === 0 || args.includes('--help')) {
        printUsage();
        process.exit(0);
    }

    const role = args.shift();
    if (!role || !ROLE_CONFIGS[role]) {
        throw new Error(`Unknown role: ${role}`);
    }

    let outputFile = null;
    if (args[0] && !args[0].startsWith('--')) {
        outputFile = args.shift();
    }

    const options = {
        baseUrl: DEFAULT_BASE_URL,
        email: ROLE_CONFIGS[role].email,
        password: ROLE_CONFIGS[role].password || DEFAULT_PASSWORD,
        loginPath: DEFAULT_LOGIN_PATH,
        loginSelector: DEFAULT_LOGIN_SELECTOR,
        navigationTimeoutMs: DEFAULT_NAVIGATION_TIMEOUT_MS,
        selectorTimeoutMs: DEFAULT_SELECTOR_TIMEOUT_MS,
        postLoginUrlPattern: DEFAULT_POST_LOGIN_URL_PATTERN,
        readySelector: ROLE_CONFIGS[role].readySelector,
        targetPath: ROLE_CONFIGS[role].targetPath,
    };

    while (args.length > 0) {
        const arg = args.shift();
        switch (arg) {
            case '--base-url':
                options.baseUrl = args.shift();
                break;
            case '--email':
                options.email = args.shift();
                break;
            case '--password':
                options.password = args.shift();
                break;
            case '--login-path':
                options.loginPath = args.shift();
                break;
            case '--login-selector':
                options.loginSelector = args.shift();
                break;
            case '--navigation-timeout-ms':
                options.navigationTimeoutMs = Number(args.shift() || '0');
                break;
            case '--selector-timeout-ms':
                options.selectorTimeoutMs = Number(args.shift() || '0');
                break;
            case '--post-login-url-pattern':
                options.postLoginUrlPattern = args.shift();
                break;
            default:
                throw new Error(`Unknown argument: ${arg}`);
        }
    }

    const resolvedOutput = path.resolve(outputFile || `.devenv/playwright-cli/${role}-state.json`);
    if (!options.baseUrl) throw new Error('--base-url is required');
    if (!options.email) throw new Error('--email is required');
    if (!options.password) throw new Error('--password is required');
    if (!options.loginPath) throw new Error('--login-path is required');
    if (!options.loginSelector) throw new Error('--login-selector is required');
    if (!options.postLoginUrlPattern) throw new Error('--post-login-url-pattern is required');
    if (!options.readySelector) throw new Error('readySelector is required');
    if (!options.targetPath) throw new Error('targetPath is required');

    return { role, outputFile: resolvedOutput, options };
}

function roleTargetUrl(options) {
    return new URL(options.targetPath, options.baseUrl).toString();
}

async function ensureLoggedIn(page, options) {
    console.log(`[pwcli-auth] opening login page: ${options.loginPath}`);
    await page.goto(new URL(options.loginPath, options.baseUrl).toString(), {
        waitUntil: 'domcontentloaded',
        timeout: options.navigationTimeoutMs,
    });
    await page.locator(options.loginSelector).first().waitFor({
        state: 'visible',
        timeout: options.selectorTimeoutMs,
    });
    console.log(`[pwcli-auth] submitting credentials for ${options.email}`);
    await page.fill('#email', options.email);
    await page.fill('#password', options.password);
    await page.locator('button[type="submit"]').first().click();

    try {
        await page.waitForURL((url) => !url.pathname.includes(options.loginPath), {
            timeout: Math.min(options.navigationTimeoutMs, 15000),
        });
    } catch (_error) {
        await page.waitForLoadState('domcontentloaded', {
            timeout: Math.min(options.navigationTimeoutMs, 5000),
        }).catch(() => null);
    }

    if (page.url().includes(options.loginPath)) {
        const flashText = (await page.locator('.alert').first().textContent().catch(() => null)) || 'No flash message';
        throw new Error(
            `Login failed: still on ${options.loginPath} after submit. ${flashText.trim()} ` +
            'Run `bash ./bin/in-env seed-dev app` for the seeded dev role accounts, or override --email/--password.'
        );
    }

    if (page.url().includes('/EditProfile')) {
        console.log('[pwcli-auth] completing required profile fields');
        const firstName = page.locator('#firstName');
        if (await firstName.count()) {
            await firstName.fill('Playwright');
            await page.fill('#lastName', 'CLI');
            await page.fill('#phone', '0400000000');
            await page.fill('#emergencyContactName', 'Emergency Contact');
            await page.fill('#emergencyContactPhone', '0411111111');
            await page.fill('#idealShiftsPerWeek', '4');
            await Promise.allSettled([
                page.waitForURL((url) => !url.pathname.includes('/EditProfile'), {
                    timeout: Math.min(options.navigationTimeoutMs, 15000),
                }),
                page.getByRole('button', { name: /^save$/i }).click(),
            ]);
            await page.waitForLoadState('domcontentloaded', {
                timeout: Math.min(options.navigationTimeoutMs, 5000),
            }).catch(() => null);
        }
    }

    if (page.url().includes('/EditProfile')) {
        throw new Error('Profile completion did not finish; still on /EditProfile');
    }
}

async function ensureRoleLanding(page, options) {
    const targetUrl = roleTargetUrl(options);
    console.log(`[pwcli-auth] verifying role landing: ${targetUrl}`);
    await page.goto(targetUrl, {
        waitUntil: 'domcontentloaded',
        timeout: options.navigationTimeoutMs,
    });
    await page.locator(options.readySelector).first().waitFor({
        state: 'visible',
        timeout: options.selectorTimeoutMs,
    });
    console.log(`[pwcli-auth] ready selector visible: ${options.readySelector}`);
}

async function main() {
    const { role, outputFile, options } = parseArgs(process.argv.slice(2));
    const browser = await chromium.launch({ headless: true });
    const context = await browser.newContext();
    const page = await context.newPage();

    try {
        await ensureLoggedIn(page, options);
        await ensureRoleLanding(page, options);
        fs.mkdirSync(path.dirname(outputFile), { recursive: true });
        await context.storageState({ path: outputFile });
        console.log(`Saved ${role} auth state: ${outputFile}`);
        console.log(`Base URL: ${options.baseUrl}`);
        console.log(`Email: ${options.email}`);
    } finally {
        if (!page.isClosed()) {
            await page.goto('about:blank', {
                waitUntil: 'domcontentloaded',
                timeout: Math.min(options.navigationTimeoutMs, 5000),
            }).catch(() => null);
        }
        await context.close().catch(() => null);
        await browser.close().catch(() => null);
    }
}

main().catch((error) => {
    console.error(error.message || error);
    process.exit(1);
});
