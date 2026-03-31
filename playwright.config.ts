import { defineConfig } from '@playwright/test';

const defaultPort = process.env.PORT || '8000';
const baseURL = process.env.BASE_URL || `http://127.0.0.1:${defaultPort}`;

export default defineConfig({
    testDir: './e2e',
    fullyParallel: false,
    workers: 1,
    retries: 1,
    reporter: 'html',

    globalSetup: './e2e/global-setup.ts',
    globalTeardown: './e2e/global-teardown.ts',

    use: {
        baseURL,
        screenshot: 'only-on-failure',
        trace: 'on-first-retry',
    },

    projects: [
        {
            name: 'chromium',
            use: { browserName: 'chromium' },
        },
    ],
});
