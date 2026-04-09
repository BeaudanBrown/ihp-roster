#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';

const DEFAULT_BASE_URL = process.env.BASE_URL || 'http://127.0.0.1:8000';
const DEFAULT_EMAIL = process.env.SCREENSHOT_EMAIL || 'dev-manager@example.com';
const DEFAULT_PASSWORD = process.env.SCREENSHOT_PASSWORD || 'password123';
const DEFAULT_LOGIN_PATH = process.env.SCREENSHOT_LOGIN_PATH || '/NewSession';
const DEFAULT_LOGIN_SELECTOR = process.env.SCREENSHOT_LOGIN_SELECTOR || '#email';
const DEFAULT_NAVIGATION_TIMEOUT_MS = Number(process.env.SCREENSHOT_NAVIGATION_TIMEOUT_MS || '120000');
const DEFAULT_SELECTOR_TIMEOUT_MS = Number(process.env.SCREENSHOT_SELECTOR_TIMEOUT_MS || '120000');
const DEFAULT_POST_LOGIN_URL_PATTERN = process.env.SCREENSHOT_POST_LOGIN_URL_PATTERN || '(Dashboard|RosterWeeks|EditProfile)';

function printUsage() {
    console.log(`Usage:
  node e2e/screenshot-page.mjs <target-path-or-url> <output-file> [options]

Options:
  --base-url <url>      Base URL for relative target paths (default: ${DEFAULT_BASE_URL})
  --email <email>       Login email (default: ${DEFAULT_EMAIL})
  --password <pass>     Login password (default: ${DEFAULT_PASSWORD})
  --login-path <path>   Login page path for authenticated flows (default: ${DEFAULT_LOGIN_PATH})
  --login-selector <css>
                        Selector that proves the login page is ready (default: ${DEFAULT_LOGIN_SELECTOR})
  --selector <css>      Wait for selector to be visible before screenshot
  --navigation-timeout-ms <ms>
                        Timeout for page navigations and post-login landing (default: ${DEFAULT_NAVIGATION_TIMEOUT_MS})
  --selector-timeout-ms <ms>
                        Timeout for login/page selectors (default: ${DEFAULT_SELECTOR_TIMEOUT_MS})
  --post-login-url-pattern <pattern>
                        Regex fragment for the expected post-login destination (default: ${DEFAULT_POST_LOGIN_URL_PATTERN})
  --wait-ms <ms>        Extra wait after navigation (default: 0)
  --no-login            Skip login/profile completion flow
  --full-page           Capture full page (default)
  --viewport <WxH>      Viewport size, e.g. 1900x1200 (default: 1900x1200)
  --help                Show this message
`);
}

function parseArgs(argv) {
    const args = [...argv];
    if (args.length === 0 || args.includes('--help')) {
        printUsage();
        process.exit(0);
    }

    const target = args.shift();
    const outputFile = args.shift();
    if (!target || !outputFile) {
        printUsage();
        process.exit(1);
    }

    const options = {
        baseUrl: DEFAULT_BASE_URL,
        email: DEFAULT_EMAIL,
        password: DEFAULT_PASSWORD,
        loginPath: DEFAULT_LOGIN_PATH,
        loginSelector: DEFAULT_LOGIN_SELECTOR,
        selector: null,
        navigationTimeoutMs: DEFAULT_NAVIGATION_TIMEOUT_MS,
        selectorTimeoutMs: DEFAULT_SELECTOR_TIMEOUT_MS,
        postLoginUrlPattern: DEFAULT_POST_LOGIN_URL_PATTERN,
        waitMs: 0,
        login: true,
        fullPage: true,
        viewport: { width: 1900, height: 1200 },
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
            case '--selector':
                options.selector = args.shift();
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
            case '--wait-ms':
                options.waitMs = Number(args.shift() || '0');
                break;
            case '--no-login':
                options.login = false;
                break;
            case '--full-page':
                options.fullPage = true;
                break;
            case '--viewport': {
                const value = args.shift() || '';
                const [widthRaw, heightRaw] = value.toLowerCase().split('x');
                const width = Number(widthRaw);
                const height = Number(heightRaw);
                if (!Number.isFinite(width) || !Number.isFinite(height)) {
                    throw new Error(`Invalid --viewport value: ${value}`);
                }
                options.viewport = { width, height };
                break;
            }
            default:
                throw new Error(`Unknown argument: ${arg}`);
        }
    }

    if (!options.baseUrl) throw new Error('--base-url is required');
    if (!options.email && options.login) throw new Error('--email is required unless --no-login is used');
    if (!options.password && options.login) throw new Error('--password is required unless --no-login is used');
    if (!options.loginPath && options.login) throw new Error('--login-path is required unless --no-login is used');
    if (!options.loginSelector && options.login) throw new Error('--login-selector is required unless --no-login is used');
    if (!options.postLoginUrlPattern && options.login) throw new Error('--post-login-url-pattern is required unless --no-login is used');
    if (!Number.isFinite(options.navigationTimeoutMs) || options.navigationTimeoutMs <= 0) throw new Error('--navigation-timeout-ms must be a positive number');
    if (!Number.isFinite(options.selectorTimeoutMs) || options.selectorTimeoutMs <= 0) throw new Error('--selector-timeout-ms must be a positive number');
    if (!Number.isFinite(options.waitMs) || options.waitMs < 0) throw new Error('--wait-ms must be a non-negative number');

    return { target, outputFile, options };
}

function toAbsoluteUrl(target, baseUrl) {
    if (target.startsWith('http://') || target.startsWith('https://')) return target;
    const normalizedPath = target.startsWith('/') ? target : `/${target}`;
    return new URL(normalizedPath, baseUrl).toString();
}

async function ensureLoggedIn(page, options) {
    await page.goto(new URL(options.loginPath, options.baseUrl).toString(), { waitUntil: 'domcontentloaded', timeout: options.navigationTimeoutMs });
    await page.locator(options.loginSelector).first().waitFor({ state: 'visible', timeout: options.selectorTimeoutMs });
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
            'For the dev app, run `bash ./bin/in-env seed-dev app` first or override --email/--password.'
        );
    }

    if (page.url().includes('/EditProfile')) {
        const firstName = page.locator('#firstName');
        if (await firstName.count()) {
            await firstName.fill('Screenshot');
            await page.fill('#lastName', 'User');
            await page.getByRole('button', { name: /save and continue/i }).click();
            await page.waitForLoadState('networkidle', { timeout: options.navigationTimeoutMs }).catch(() => null);
        }
    }
}

async function main() {
    const { target, outputFile, options } = parseArgs(process.argv.slice(2));
    const targetUrl = toAbsoluteUrl(target, options.baseUrl);
    const outputPath = path.resolve(outputFile);

    const browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({ viewport: options.viewport });
    const page = await context.newPage();

    try {
        if (options.login) {
            await ensureLoggedIn(page, options);
        }

        await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: options.navigationTimeoutMs });
        if (options.selector) {
            await page.locator(options.selector).first().waitFor({ state: 'visible', timeout: options.selectorTimeoutMs });
        }
        if (options.waitMs > 0) {
            await page.waitForTimeout(options.waitMs);
        }

        fs.mkdirSync(path.dirname(outputPath), { recursive: true });
        await page.screenshot({ path: outputPath, fullPage: options.fullPage });
        console.log(`Saved screenshot: ${outputPath}`);
        console.log(`URL: ${targetUrl}`);
    } finally {
        await context.close();
        await browser.close();
    }
}

main().catch((error) => {
    console.error(error.message || error);
    process.exit(1);
});
