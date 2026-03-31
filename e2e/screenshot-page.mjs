#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';

const DEFAULT_BASE_URL = process.env.BASE_URL || `http://127.0.0.1:${process.env.PORT || '8000'}`;
const DEFAULT_EMAIL = process.env.SCREENSHOT_EMAIL || 'e2e-test@example.com';
const DEFAULT_PASSWORD = process.env.SCREENSHOT_PASSWORD || 'test-password-123';

function printUsage() {
    console.log(`Usage:
  node e2e/screenshot-page.mjs <target-path-or-url> <output-file> [options]

Options:
  --base-url <url>      Base URL for relative target paths (default: ${DEFAULT_BASE_URL})
  --email <email>       Login email (default: ${DEFAULT_EMAIL})
  --password <pass>     Login password (default: ${DEFAULT_PASSWORD})
  --selector <css>      Wait for selector to be visible before screenshot
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
        selector: null,
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
            case '--selector':
                options.selector = args.shift();
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
    if (!Number.isFinite(options.waitMs) || options.waitMs < 0) throw new Error('--wait-ms must be a non-negative number');

    return { target, outputFile, options };
}

function toAbsoluteUrl(target, baseUrl) {
    if (target.startsWith('http://') || target.startsWith('https://')) return target;
    const normalizedPath = target.startsWith('/') ? target : `/${target}`;
    return new URL(normalizedPath, baseUrl).toString();
}

async function ensureLoggedIn(page, options) {
    await page.goto(new URL('/NewSession', options.baseUrl).toString(), { waitUntil: 'networkidle' });
    await page.fill('#email', options.email);
    await page.fill('#password', options.password);
    await page.locator('button[type="submit"]').first().click();
    try {
        await page.waitForURL(/\/(Dashboard|RosterWeeks|EditProfile)/, { timeout: 10_000 });
    } catch (_error) {
        await page.waitForLoadState('networkidle');
    }

    if (page.url().includes('/NewSession')) {
        const flashText = (await page.locator('.alert').first().textContent().catch(() => null)) || 'No flash message';
        throw new Error(`Login failed: still on /NewSession after submit. ${flashText.trim()}`);
    }

    if (page.url().includes('/EditProfile')) {
        const firstName = page.locator('#firstName');
        if (await firstName.count()) {
            await firstName.fill('Screenshot');
            await page.fill('#lastName', 'User');
            await page.getByRole('button', { name: /save and continue/i }).click();
            await page.waitForLoadState('networkidle');
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

        await page.goto(targetUrl, { waitUntil: 'networkidle' });
        if (options.selector) {
            await page.locator(options.selector).first().waitFor({ state: 'visible', timeout: 10_000 });
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
