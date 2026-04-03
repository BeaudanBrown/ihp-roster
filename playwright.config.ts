import { defineConfig, devices } from '@playwright/test';

const baseURL = process.env.E2E_BASE_URL ?? 'http://127.0.0.1:8000';
const outputDir = process.env.PLAYWRIGHT_OUTPUT_DIR ?? 'test-results';
const htmlReportDir = process.env.PLAYWRIGHT_HTML_REPORT_DIR ?? 'playwright-report';

export default defineConfig({
    testDir: './e2e',
    fullyParallel: false,
    workers: 1,
    retries: 1,
    outputDir,
    reporter: [['html', { open: 'never', outputFolder: htmlReportDir }]],

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
            testIgnore: [/.*mobile-experience\.spec\.ts/, /.*roster-mobile\.spec\.ts/],
            use: { browserName: 'chromium' },
        },
        {
            name: 'mobile-chromium',
            testMatch: [/.*mobile-experience\.spec\.ts/, /.*roster-mobile\.spec\.ts/],
            use: {
                ...devices['Pixel 7'],
                browserName: 'chromium',
            },
        },
        {
            name: 'galaxy-s9-plus',
            testMatch: [/.*mobile-experience\.spec\.ts/, /.*roster-mobile\.spec\.ts/],
            use: {
                browserName: 'chromium',
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
            testMatch: [/.*mobile-experience\.spec\.ts/, /.*roster-mobile\.spec\.ts/],
            use: {
                ...devices['iPad Mini'],
                browserName: 'chromium',
            },
        },
    ],
});
