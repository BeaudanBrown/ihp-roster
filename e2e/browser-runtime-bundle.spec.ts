import { expect, test } from '@playwright/test';
import { gotoWhenReady } from './support/runtime';

type NativeTimerWindow = Window & {
    __nativeSetInterval?: Window['setInterval'];
    __nativeSetTimeout?: Window['setTimeout'];
};

test.describe('ordered browser runtime bundle', () => {
    test('loads one production app graph and the standalone development live-reload client', async ({ page }) => {
        await gotoWhenReady(page, '/NewSession', '#email');

        const runtime = await page.evaluate(() => ({
            appAssets: performance.getEntriesByType('resource')
                .map((entry) => new URL(entry.name).pathname)
                .filter((pathname) => /^\/static\/app(?:-[^/]*)?\.js$/.test(pathname)),
            scriptAssets: Array.from(document.scripts)
                .map((script) => new URL(script.src, document.baseURI).pathname),
            reloadUrl: document.querySelector<HTMLScriptElement>('#livereload-script')?.dataset.ws,
            hasDevelopmentTimerTracking: 'allTimeouts' in window || 'clearAllTimeouts' in window
                || 'unsafeSetTimeout' in window,
        }));

        expect(runtime.appAssets).toEqual(['/static/app.js']);
        expect(runtime.hasDevelopmentTimerTracking).toBe(false);
        expect(runtime.scriptAssets.filter((path) => path === '/static/dev-live-reload.js')).toHaveLength(1);
        expect(runtime.scriptAssets).not.toContain('/static/dev-timer-tracking.js');
        expect(runtime.scriptAssets).not.toContain('/static/livereload.js');
        expect(runtime.reloadUrl).toMatch(/^wss?:\/\//);
    });

    test('keeps native timers in both the production graph and active development client', async ({ page }) => {
        await page.routeWebSocket('ws://runtime.test/reload', (socket) => {
            socket.send('reload_assets');
        });
        await page.route('http://runtime.test/', (route) => route.fulfill({
            body: '<!doctype html><html><body></body></html>', contentType: 'text/html',
        }));
        await page.goto('http://runtime.test/');
        await page.evaluate(() => {
            const target = window as NativeTimerWindow;
            target.__nativeSetInterval = window.setInterval;
            target.__nativeSetTimeout = window.setTimeout;
        });

        const timerState = () => page.evaluate(() => {
            const target = window as NativeTimerWindow;
            return {
                intervalIsNative: window.setInterval === target.__nativeSetInterval,
                timeoutIsNative: window.setTimeout === target.__nativeSetTimeout,
                hasTrackedIntervals: 'allIntervals' in window,
                hasTrackedTimeouts: 'allTimeouts' in window,
            };
        });
        const nativeState = {
            intervalIsNative: true,
            timeoutIsNative: true,
            hasTrackedIntervals: false,
            hasTrackedTimeouts: false,
        };
        await page.addScriptTag({ path: 'static/app.js' });
        expect(await timerState()).toEqual(nativeState);

        await page.route('http://runtime.test/dev-live-reload.js', (route) => route.fulfill({
            path: 'static/dev-live-reload.js', contentType: 'application/javascript',
        }));
        await page.route('http://runtime.test/style.css*', (route) => route.fulfill({
            body: '', contentType: 'text/css',
        }));
        await page.evaluate(() => {
            const stylesheet = document.createElement('link');
            stylesheet.rel = 'stylesheet';
            stylesheet.href = 'http://runtime.test/style.css';
            document.head.append(stylesheet);
            const script = document.createElement('script');
            script.src = 'http://runtime.test/dev-live-reload.js';
            script.dataset.ws = 'ws://runtime.test/reload';
            document.head.append(script);
        });
        await expect(page.locator('link[rel="stylesheet"]')).toHaveAttribute('href', /[?&]refresh=\d+/);
        expect(await timerState()).toEqual(nativeState);
    });
});
