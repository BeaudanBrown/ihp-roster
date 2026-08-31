import { expect, test } from '@playwright/test';
import { gotoWhenReady } from './support/runtime';
import { E2E_TIMEOUT } from './timeouts';

type DevelopmentTimerWindow = Window & {
    allTimeouts?: number[];
    clearAllTimeouts?: () => void;
    unsafeSetTimeout?: Window['setTimeout'];
};

test.describe('ordered browser runtime bundle', () => {
    test('loads one production app graph and orders development timer compatibility before live reload', async ({ page }) => {
        await gotoWhenReady(page, '/NewSession', '#email');

        const runtime = await page.evaluate(() => ({
            appAssets: performance.getEntriesByType('resource')
                .map((entry) => new URL(entry.name).pathname)
                .filter((pathname) => /^\/static\/app(?:-[^/]*)?\.js$/.test(pathname)),
            scriptAssets: Array.from(document.scripts)
                .map((script) => new URL(script.src, document.baseURI).pathname),
            hasDevelopmentTimerTracking: Array.isArray((window as DevelopmentTimerWindow).allTimeouts)
                && typeof (window as DevelopmentTimerWindow).clearAllTimeouts === 'function'
                && typeof (window as DevelopmentTimerWindow).unsafeSetTimeout === 'function',
        }));

        expect(runtime.appAssets).toEqual(['/static/app.js']);
        expect(runtime.hasDevelopmentTimerTracking).toBe(true);
        expect(runtime.scriptAssets.indexOf('/static/dev-timer-tracking.js')).toBeGreaterThanOrEqual(0);
        expect(runtime.scriptAssets.indexOf('/static/dev-timer-tracking.js')).toBeLessThan(
            runtime.scriptAssets.indexOf('/static/livereload.js'),
        );
        expect(runtime.scriptAssets.indexOf('/static/livereload.js')).toBeLessThan(
            runtime.scriptAssets.indexOf('/static/app.js'),
        );
    });

    test('keeps native production timers and confines tracking to the development asset', async ({ page }) => {
        await page.setContent('<!doctype html><html><body></body></html>');
        await page.evaluate(() => {
            const target = window as Window & {
                __nativeSetInterval?: Window['setInterval'];
                __nativeSetTimeout?: Window['setTimeout'];
            };
            target.__nativeSetInterval = window.setInterval;
            target.__nativeSetTimeout = window.setTimeout;
        });

        await page.addScriptTag({ path: 'static/app.js' });

        expect(await page.evaluate(() => {
            const target = window as Window & {
                __nativeSetInterval?: Window['setInterval'];
                __nativeSetTimeout?: Window['setTimeout'];
            };
            return {
                intervalIsNative: window.setInterval === target.__nativeSetInterval,
                timeoutIsNative: window.setTimeout === target.__nativeSetTimeout,
                hasTrackedIntervals: 'allIntervals' in window,
                hasTrackedTimeouts: 'allTimeouts' in window,
            };
        })).toEqual({
            intervalIsNative: true,
            timeoutIsNative: true,
            hasTrackedIntervals: false,
            hasTrackedTimeouts: false,
        });

        await page.addScriptTag({ path: 'static/dev-timer-tracking.js' });
        expect(await page.evaluate((delayMs) => {
            const target = window as DevelopmentTimerWindow;
            const timeoutId = window.setTimeout(() => undefined, delayMs);
            const tracked = target.allTimeouts?.includes(timeoutId) ?? false;
            target.clearAllTimeouts?.();
            return {
                tracked,
                cleared: target.allTimeouts?.length === 0,
            };
        }, E2E_TIMEOUT.action)).toEqual({ tracked: true, cleared: true });
    });
});
