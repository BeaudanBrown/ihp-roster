import { expect, Page, test } from '@playwright/test';
import { UiRegionDom, UiRegionEvents } from '../frontend/ts/generated/contracts';
import { gotoWhenReady } from './test-helpers';

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
    test('adapts HTMX lifecycle events only for marked regions and applies transition phases', async ({ page }) => {
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

            plainBoundary.dispatchEvent(new CustomEvent('htmx:beforeSwap', {
                bubbles: true,
                detail: { target: plainBoundary, elt: plainBoundary },
            }));
            const afterPlainCount = seen.length;

            markedRegion.dispatchEvent(new CustomEvent('htmx:beforeRequest', {
                bubbles: true,
                detail: { elt: markedRegion },
            }));
            markedRegion.dispatchEvent(new CustomEvent('htmx:beforeSwap', {
                bubbles: true,
                detail: { target: markedRegion, elt: markedRegion },
            }));
            const beforeSwapClasses = Array.from(markedRegion.classList);

            markedRegion.dispatchEvent(new CustomEvent('htmx:afterSwap', {
                bubbles: true,
                detail: { target: markedRegion, elt: markedRegion },
            }));
            const afterSwapClasses = Array.from(markedRegion.classList);

            markedRegion.dispatchEvent(new CustomEvent('htmx:afterSettle', {
                bubbles: true,
                detail: { target: markedRegion, elt: markedRegion },
            }));
            const settledClasses = Array.from(markedRegion.classList);

            return {
                afterPlainCount,
                seen,
                beforeSwapClasses,
                afterSwapClasses,
                settledClasses,
            };
        }, { dom: UiRegionDom, events: UiRegionEvents });

        expect(result.afterPlainCount).toBe(0);
        expect(result.seen.map((event) => event.type)).toEqual([
            UiRegionEvents.requestStart,
            UiRegionEvents.beforeSwap,
            UiRegionEvents.afterSwap,
            UiRegionEvents.settle,
        ]);
        expect(result.seen.every((event) => event.regionId === 'marked-region')).toBe(true);
        expect(result.seen.map((event) => event.htmxEventName)).toEqual([
            'htmx:beforeRequest',
            'htmx:beforeSwap',
            'htmx:afterSwap',
            'htmx:afterSettle',
        ]);
        expect(result.beforeSwapClasses).toEqual(expect.arrayContaining(['app-region-transition', 'app-region-transition-fade', 'app-region-transition-before-swap']));
        expect(result.afterSwapClasses).toEqual(expect.arrayContaining(['app-region-transition', 'app-region-transition-fade', 'app-region-transition-after-swap']));
        expect(result.settledClasses).not.toContain('app-region-transition');
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
        }, { dom: UiRegionDom });

        expect(result.retryBusy).toBe('false');
        expect(result.retryText).toContain('This section took too long to load.');
        expect(result.retryButtonHxGet).toBe('/SyntheticRetry');
        expect(result.noRetryText).toBe('loading');
        expect(result.noRetryHasButton).toBe(false);
    });
});
