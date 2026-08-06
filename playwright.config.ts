import { defineConfig, devices } from '@playwright/test';
import { E2E_TIMEOUT } from './e2e/timeouts';

declare const process: { env: Record<string, string | undefined> };

const baseURL = process.env.E2E_BASE_URL ?? 'http://127.0.0.1:8000';
const outputDir = process.env.PLAYWRIGHT_OUTPUT_DIR ?? 'test-results';
const htmlReportDir = process.env.PLAYWRIGHT_HTML_REPORT_DIR ?? 'playwright-report';
const blobReportDir = process.env.PLAYWRIGHT_BLOB_REPORT_DIR;
const includeScreenshotSpecs = process.env.E2E_INCLUDE_SCREENSHOTS === '1';
const configuredWorkers = Number.parseInt(process.env.PLAYWRIGHT_WORKERS ?? '1', 10);
const workers = Number.isFinite(configuredWorkers) && configuredWorkers > 0 ? configuredWorkers : 1;
const configuredRetries = Number.parseInt(process.env.PLAYWRIGHT_RETRIES ?? '1', 10);
const retries = Number.isFinite(configuredRetries) && configuredRetries >= 0 ? configuredRetries : 1;
const fullyParallel = process.env.PLAYWRIGHT_FULLY_PARALLEL === '1';
const e2eTier = process.env.E2E_TIER ?? 'full';
if (!['fast', 'full'].includes(e2eTier)) {
    throw new Error(`E2E_TIER must be fast or full, got: ${e2eTier}`);
}
const mobileTestFiles = [
    /.*mobile-experience\.spec\.ts/,
    /.*pwa-install\.spec\.ts/,
    /.*roster-mobile\.spec\.ts/,
    /.*roster-template-designer\.spec\.ts/,
    /.*roster-template-application\.spec\.ts/,
    ...(includeScreenshotSpecs ? [/.*roster-mobile-screenshots\.spec\.ts/] : []),
];

const reporter = blobReportDir
    ? [['blob', { outputDir: blobReportDir }] as const]
    : [['html', { open: 'never', outputFolder: htmlReportDir }] as const];

export default defineConfig({
    testDir: './e2e',
    fullyParallel,
    workers,
    retries,
    maxFailures: e2eTier === 'fast' ? 1 : 0,
    timeout: E2E_TIMEOUT.test,
    expect: {
        timeout: E2E_TIMEOUT.assertion,
    },
    outputDir,
    reporter,

    globalSetup: './e2e/global-setup.ts',
    globalTeardown: './e2e/global-teardown.ts',

    use: {
        baseURL,
        screenshot: 'only-on-failure',
        trace: 'on-first-retry',
    },

    projects: [
        {
            name: 'desktop-chromium',
            testIgnore: [
                /.*mobile-experience\.spec\.ts/,
                /.*roster-mobile\.spec\.ts/,
                /.*roster-mobile-screenshots\.spec\.ts/,
            ],
            use: { browserName: 'chromium' as const },
        },
        {
            name: 'mobile-chromium',
            testMatch: mobileTestFiles,
            use: {
                ...devices['Pixel 7'],
                browserName: 'chromium' as const,
            },
        },
        {
            name: 'galaxy-s9-plus',
            testMatch: mobileTestFiles,
            grepInvert: /@canonical-mobile/,
            use: {
                browserName: 'chromium' as const,
                viewport: { width: 360, height: 740 },
                screen: { width: 360, height: 740 },
                deviceScaleFactor: 4,
                isMobile: true,
                hasTouch: true,
                userAgent:
                    'Mozilla/5.0 (Linux; Android 10; SM-G965F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
            },
        },
        {
            name: 'tablet-chromium',
            testMatch: mobileTestFiles,
            grepInvert: /@canonical-mobile/,
            use: {
                ...devices['iPad Mini'],
                browserName: 'chromium' as const,
            },
        },
    ].filter((project) => e2eTier === 'full' || ['desktop-chromium', 'mobile-chromium'].includes(project.name)),
});
