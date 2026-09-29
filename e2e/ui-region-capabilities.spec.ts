import { expect, Page, test } from '@playwright/test';
import {
    fragmentDomAttr,
    lazyRetryDomAttr,
    lazySurfaceDomAttr,
    regionAfterSwapEvent,
    regionBeforeSwapEvent,
    regionRequestStartEvent,
    regionSettleEvent,
    regionTransitionDomAttr,
    regionLoadingDomAttr,
    regionBackgroundDomAttr,
    requestLoadingStatusDomAttr,
} from '../frontend/ts/generated/contracts';
import { gotoWhenReady } from './support/runtime';
import { loginAs } from './support/session';

type HtmxWindow = Window & { htmx?: { process: (element: HTMLElement) => void } };

type RegionEventRecord = {
    type: string;
    lifecycleEvent: string;
    htmxEventName: string;
    regionId: string;
};

async function openRuntimePage(page: Page) {
    await gotoWhenReady(page, '/NewSession', '#email');
}

test.describe('Declarative UI region capabilities', () => {
    test('adapts registered lifecycle events without exit motion and completes arrivals after settlement', async ({ page }) => {
        await openRuntimePage(page);

        const result = await page.evaluate(({ dom, events }) => {
            const seen: RegionEventRecord[] = [];
            document.body.insertAdjacentHTML(
                'beforeend',
                `
                    <section id="marked-region" ${dom.fragment}="true" ${dom.transition}="fade">marked</section>
                    <section id="plain-htmx-boundary">plain</section>
                `,
            );

            const markedRegion = document.getElementById('marked-region');
            const plainBoundary = document.getElementById('plain-htmx-boundary');
            if (!(markedRegion instanceof HTMLElement) || !(plainBoundary instanceof HTMLElement)) {
                throw new Error('Synthetic regions were not inserted');
            }

            Object.values(events).forEach((eventName) => {
                markedRegion.addEventListener(eventName, (event) => {
                    const detail = (event as CustomEvent).detail;
                    seen.push({
                        type: event.type,
                        lifecycleEvent: detail.lifecycleEvent,
                        htmxEventName: detail.htmxEventName,
                        regionId: detail.region.id,
                    });
                });
            });

            const xhr = new XMLHttpRequest();
            plainBoundary.dispatchEvent(new CustomEvent('htmx:beforeSwap', {
                bubbles: true,
                detail: { target: plainBoundary, elt: plainBoundary },
            }));
            const afterPlainCount = seen.length;

            markedRegion.dispatchEvent(new CustomEvent('htmx:beforeRequest', {
                bubbles: true,
                detail: { target: markedRegion, elt: markedRegion, xhr, requestConfig: { triggeringEvent: new Event('click') } },
            }));
            markedRegion.dispatchEvent(new CustomEvent('htmx:beforeSwap', {
                bubbles: true,
                detail: { target: markedRegion, elt: markedRegion, xhr },
            }));
            const beforeSwapClasses = Array.from(markedRegion.classList);

            markedRegion.dispatchEvent(new CustomEvent('htmx:afterSwap', {
                bubbles: true,
                detail: { target: markedRegion, elt: markedRegion, xhr },
            }));
            const afterSwapClasses = Array.from(markedRegion.classList);

            markedRegion.dispatchEvent(new CustomEvent('htmx:afterSettle', {
                bubbles: true,
                detail: { target: markedRegion, elt: markedRegion, xhr },
            }));
            const settledClasses = Array.from(markedRegion.classList);

            return {
                afterPlainCount,
                seen,
                beforeSwapClasses,
                afterSwapClasses,
                settledClasses,
            };
        }, {
            dom: {
                fragment: fragmentDomAttr,
                lazyRetry: lazyRetryDomAttr,
                lazySurface: lazySurfaceDomAttr,
                transition: regionTransitionDomAttr,
            },
            events: {
                requestStart: regionRequestStartEvent,
                beforeSwap: regionBeforeSwapEvent,
                afterSwap: regionAfterSwapEvent,
                settle: regionSettleEvent,
            },
        });

        expect(result.afterPlainCount).toBe(0);
        expect(result.seen.map((event) => event.type)).toEqual([
            regionRequestStartEvent,
            regionBeforeSwapEvent,
            regionAfterSwapEvent,
            regionSettleEvent,
        ]);
        expect(result.seen.every((event) => event.regionId === 'marked-region')).toBe(true);
        expect(result.seen.map((event) => event.htmxEventName)).toEqual([
            'htmx:beforeRequest',
            'htmx:beforeSwap',
            'htmx:afterSwap',
            'htmx:afterSettle',
        ]);
        expect(result.beforeSwapClasses).not.toContain('app-region-transition');
        expect(result.afterSwapClasses).not.toContain('app-region-transition');
        expect(result.settledClasses).toEqual(expect.arrayContaining(['app-region-transition', 'app-region-transition-fade', 'app-region-transition-after-swap']));
        await expect(page.locator('#marked-region')).not.toHaveClass(/app-region-transition/);
    });

    test('real concurrent HTMX requests share delayed status until the last completion', async ({ page }) => {
        await openRuntimePage(page);
        let releaseFirst!: () => void;
        let releaseSecond!: () => void;
        const first = new Promise<void>((resolve) => { releaseFirst = resolve; });
        const second = new Promise<void>((resolve) => { releaseSecond = resolve; });
        await page.route('**/MotionFirst', async (route) => { await first; await route.fulfill({ contentType: 'text/html', body: 'first complete' }); });
        await page.route('**/MotionSecond', async (route) => { await second; await route.fulfill({ contentType: 'text/html', body: 'second complete' }); });
        await page.evaluate(({ fragment, loading, status }) => {
            document.body.insertAdjacentHTML('beforeend', `
                <div ${status}="true" hidden>Loading…</div>
                <section id="motion-first" ${fragment}="true" ${loading}="shared-status">First</section>
                <section id="motion-second" ${fragment}="true" ${loading}="shared-status">Second</section>
                <button id="motion-first-button" hx-get="/MotionFirst" hx-target="#motion-first">First</button>
                <button id="motion-second-button" hx-get="/MotionSecond" hx-target="#motion-second">Second</button>`);
            (window as HtmxWindow).htmx!.process(document.body);
        }, { fragment: fragmentDomAttr, loading: regionLoadingDomAttr, status: requestLoadingStatusDomAttr });
        try {
            await page.locator('#motion-first-button').click();
            await page.locator('#motion-second-button').click();
            await expect(page.locator('#motion-first')).toHaveClass(/app-region-pending/);
            await expect(page.locator('#motion-second')).toHaveClass(/app-region-pending/);
            await expect(page.locator(`[${requestLoadingStatusDomAttr}]`)).toBeVisible();
            releaseFirst();
            await expect(page.locator('#motion-first')).toHaveText('first complete');
            await expect(page.locator('#motion-first')).not.toHaveClass(/app-region-pending/);
            await expect(page.locator(`[${requestLoadingStatusDomAttr}]`)).toBeVisible();
            releaseSecond();
            await expect(page.locator('#motion-second')).toHaveText('second complete');
            await expect(page.locator(`[${requestLoadingStatusDomAttr}]`)).toBeHidden();
            await expect(page.locator('#motion-second')).not.toHaveClass(/app-region-pending/);
            await expect(page.locator('#motion-first')).not.toHaveClass(/app-region-transition/);
        } finally { releaseFirst(); releaseSecond(); }
    });

    test('native HTMX keeps the latest navigation without waiting for unrelated writes', async ({ page }) => {
        await openRuntimePage(page);
        let releaseWrite!: () => void;
        let releaseFirst!: () => void;
        const write = new Promise<void>((resolve) => { releaseWrite = resolve; });
        const first = new Promise<void>((resolve) => { releaseFirst = resolve; });
        const requests: string[] = [];
        await page.route('**/MotionWrite', async (route) => {
            requests.push('write');
            await write;
            await route.fulfill({ status: 204, body: '' });
        });
        await page.route('**/MotionNavigate*', async (route) => {
            const choice = new URL(route.request().url()).searchParams.get('choice') ?? '';
            requests.push(choice);
            if (choice === 'one') await first;
            await route.fulfill({ contentType: 'text/html', body: `choice ${choice}` });
        });
        await page.evaluate(({ fragment }) => {
            document.body.insertAdjacentHTML('beforeend', `
                <section id="motion-navigation" ${fragment}="true">Original</section>
                <button id="motion-write" hx-post="/MotionWrite" hx-swap="none">Write</button>
                <button id="motion-next-one" hx-get="/MotionNavigate?choice=one" hx-target="#motion-navigation" hx-sync="#motion-navigation:replace">One</button>
                <button id="motion-next-two" hx-get="/MotionNavigate?choice=two" hx-target="#motion-navigation" hx-sync="#motion-navigation:replace">Two</button>`);
            (window as HtmxWindow).htmx!.process(document.body);
        }, { fragment: fragmentDomAttr });
        try {
            await page.locator('#motion-write').click();
            await expect.poll(() => requests).toEqual(['write']);
            await page.locator('#motion-next-one').click();
            await expect.poll(() => requests).toEqual(['write', 'one']);
            const firstAborted = page.waitForEvent('requestfailed', (request) => request.url().includes('/MotionNavigate?choice=one'));
            await page.locator('#motion-next-two').click();
            await firstAborted;
            await expect(page.locator('#motion-navigation')).toHaveText('choice two');
            expect(requests).toEqual(['write', 'one', 'two']);
        } finally { releaseWrite(); releaseFirst(); }
    });

    for (const outcome of ['error', 'abort'] as const) {
        test(`real HTMX ${outcome} clears dimming and the below-header status`, async ({ page }) => {
            await loginAs(page, 'e2e-test@example.com', 'test-password-123');
            let release!: () => void;
            const held = new Promise<void>(resolve => { release = resolve; });
            await page.route('**/MotionTerminal', async route => {
                await held;
                await route.fulfill({ status: 500, body: 'Expected test failure' });
            });
            await page.evaluate(({ fragment, loading }) => {
                document.body.insertAdjacentHTML('beforeend', `
                    <section id="motion-terminal" ${fragment}="true" ${loading}="shared-status">Original</section>
                    <button id="motion-terminal-button" hx-get="/MotionTerminal" hx-target="#motion-terminal">Request</button>`);
                (window as HtmxWindow).htmx!.process(document.body);
            }, { fragment: fragmentDomAttr, loading: regionLoadingDomAttr });
            try {
                await page.locator('#motion-terminal-button').click();
                await expect(page.locator('#motion-terminal')).toHaveClass(/app-region-pending/);
                const status = page.locator(`[${requestLoadingStatusDomAttr}]`);
                await expect(status).toBeVisible();
                // Verify real authenticated placement, not merely CSS visibility.
                await page.evaluate(() => window.scrollTo(0, 0));
                const placement = await status.evaluate(host => {
                    const box = host.getBoundingClientRect();
                    const header = host.closest('header')!.getBoundingClientRect();
                    return { top: box.top, bottom: box.bottom, headerBottom: header.bottom, viewport: window.innerHeight };
                });
                expect(placement.top).toBeGreaterThanOrEqual(placement.headerBottom);
                expect(placement.top - placement.headerBottom).toBeLessThan(32);
                expect(placement.bottom).toBeLessThanOrEqual(placement.viewport);
                if (outcome === 'abort') await page.locator('#motion-terminal-button').dispatchEvent('htmx:abort');
                else release();
                await expect(page.locator('#motion-terminal')).not.toHaveClass(/app-region-pending/);
                await expect(status).toBeHidden();
                await expect(page.locator('#motion-terminal')).toHaveText('Original');
            } finally { release(); }
        });
    }

    test('background HTMX loading remains quiet even with explicit shared status', async ({ page }) => {
        await openRuntimePage(page);
        await page.route('**/MotionBackground', (route) => route.fulfill({ contentType: 'text/html', body: 'background complete' }));
        await page.evaluate(({ fragment, loading, background }) => {
            document.body.insertAdjacentHTML('beforeend', `<section id="motion-background" ${fragment}="true" ${loading}="shared-status" ${background}="true" hx-get="/MotionBackground" hx-trigger="load">Original</section>`);
            const region = document.getElementById('motion-background')!;
            let effects = 0;
            new MutationObserver(() => { if (region.classList.contains('app-region-pending') || region.classList.contains('app-region-transition')) effects++; region.dataset.effectCount = String(effects); }).observe(region, { attributes: true, attributeFilter: ['class'] });
            region.dataset.effectCount = '0';
            (window as HtmxWindow).htmx!.process(region);
        }, { fragment: fragmentDomAttr, loading: regionLoadingDomAttr, background: regionBackgroundDomAttr });
        await expect(page.locator('#motion-background')).toHaveText('background complete');
        await expect(page.locator('#motion-background')).not.toHaveClass(/htmx-settling/);
        await expect(page.locator('#motion-background')).toHaveAttribute('data-effect-count', '0');
    });

    test('renders lazy retry UI from region errors and leaves retry-disabled regions alone', async ({ page }) => {
        await openRuntimePage(page);

        const result = await page.evaluate(({ dom }) => {
            document.body.insertAdjacentHTML(
                'beforeend',
                `
                    <section id="retry-region" ${dom.fragment}="true" ${dom.lazySurface}="true" ${dom.lazyRetry}="true" ${dom.transition}="none" hx-get="/SyntheticRetry">loading</section>
                    <section id="no-retry-region" ${dom.fragment}="true" ${dom.lazySurface}="true" ${dom.transition}="none" hx-get="/SyntheticNoRetry">loading</section>
                `,
            );

            const retryRegion = document.getElementById('retry-region');
            const noRetryRegion = document.getElementById('no-retry-region');
            if (!(retryRegion instanceof HTMLElement) || !(noRetryRegion instanceof HTMLElement)) {
                throw new Error('Synthetic lazy regions were not inserted');
            }

            retryRegion.dispatchEvent(new CustomEvent('htmx:timeout', {
                bubbles: true,
                detail: { target: retryRegion, elt: retryRegion },
            }));
            noRetryRegion.dispatchEvent(new CustomEvent('htmx:timeout', {
                bubbles: true,
                detail: { target: noRetryRegion, elt: noRetryRegion },
            }));

            const retryButton = retryRegion.querySelector('.app-lazy-surface-retry');
            return {
                retryBusy: retryRegion.getAttribute('aria-busy'),
                retryText: retryRegion.textContent,
                retryButtonHxGet: retryButton?.getAttribute('hx-get') ?? null,
                noRetryText: noRetryRegion.textContent,
                noRetryHasButton: noRetryRegion.querySelector('.app-lazy-surface-retry') !== null,
            };
        }, {
            dom: {
                fragment: fragmentDomAttr,
                lazyRetry: lazyRetryDomAttr,
                lazySurface: lazySurfaceDomAttr,
                transition: regionTransitionDomAttr,
            },
        });

        expect(result.retryBusy).toBe('false');
        expect(result.retryText).toContain('This section took too long to load.');
        expect(result.retryButtonHxGet).toBe('/SyntheticRetry');
        expect(result.noRetryText).toBe('loading');
        expect(result.noRetryHasButton).toBe(false);
    });
});
