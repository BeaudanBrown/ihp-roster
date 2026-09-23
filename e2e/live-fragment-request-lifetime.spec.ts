import { test, expect, type Route } from '@playwright/test';
import {
    liveFragmentsRefreshEvent,
    surfaceConfigDomAttr,
} from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from './timeouts';
import { openRoster } from './support/roster';

test.describe('Live fragment request lifetime', () => {
    test.setTimeout(E2E_TIMEOUT.slowTest);

    test('a delayed response cannot mutate an identical remounted surface instance', async ({ page }) => {
        await openRoster(page, { ensureEditable: false });

        const request = await page.evaluate(({ configAttr }) => {
            const owners = Array.from(document.querySelectorAll<HTMLElement>(`[${configAttr}]`));
            for (const owner of owners) {
                const rawConfig = owner.getAttribute(configAttr);
                if (!rawConfig) continue;
                const config = JSON.parse(rawConfig);
                const fragment = config.fragments?.find((candidate: { targetId?: unknown; url?: unknown }) =>
                    typeof candidate.targetId === 'string'
                    && typeof candidate.url === 'string'
                    && document.getElementById(candidate.targetId),
                );
                if (fragment && config.subscription) {
                    return {
                        scope: config.subscription.scope,
                        scopeKey: config.scopeKey,
                        fragmentKey: fragment.fragmentKey,
                        targetId: fragment.targetId as string,
                        url: new URL(fragment.url as string, window.location.href).toString(),
                    };
                }
            }
            throw new Error('Expected a mounted subscribing live fragment');
        }, { configAttr: surfaceConfigDomAttr });

        let releaseDelayedRoute!: (route: Route) => void;
        const delayedRoutePromise = new Promise<Route>((resolve) => { releaseDelayedRoute = resolve; });
        await page.route(request.url, async (route) => {
            releaseDelayedRoute(route);
        });
        const refreshRequest = page.waitForRequest((candidate) => candidate.url() === request.url);
        await page.evaluate(({ eventName, detail }) => {
            document.dispatchEvent(new CustomEvent(eventName, { detail }));
        }, {
            eventName: liveFragmentsRefreshEvent,
            detail: { scope: request.scope, scopeKey: request.scopeKey, fragments: [request.fragmentKey] },
        });
        await refreshRequest;
        const delayedRoute = await delayedRoutePromise;

        await page.evaluate(({ configAttr, targetId }) => {
            const target = document.getElementById(targetId);
            const oldOwner = target?.closest<HTMLElement>(`[${configAttr}]`);
            if (!target || !oldOwner) throw new Error('Expected live fragment owner');
            const replacementOwner = oldOwner.cloneNode(true) as HTMLElement;
            const replacementTarget = replacementOwner.querySelector<HTMLElement>(`#${CSS.escape(targetId)}`);
            if (!replacementTarget) throw new Error('Expected cloned live fragment target');
            replacementTarget.dataset.e2eMountedLifetime = 'replacement';
            oldOwner.replaceWith(replacementOwner);
            const lifecycle = (window as Window & {
                appPageLifecycle?: { dispatchPageReady?: (detail: unknown) => void };
            }).appPageLifecycle;
            if (!lifecycle?.dispatchPageReady) throw new Error('Expected app page lifecycle');
            lifecycle.dispatchPageReady({
                source: 'e2e-identical-remount',
                target: replacementOwner,
                isFullPage: false,
            });
        }, { configAttr: surfaceConfigDomAttr, targetId: request.targetId });

        await delayedRoute.fulfill({
            status: 200,
            contentType: 'text/html',
            headers: { 'HX-Refresh': 'true' },
            body: `<section id="${request.targetId}">stale delayed response</section>`,
        });
        await page.evaluate(() => new Promise<void>((resolve) => window.requestAnimationFrame(() => resolve())));

        const replacement = page.locator(`#${request.targetId}`);
        await expect(replacement).toHaveAttribute('data-e2e-mounted-lifetime', 'replacement');
        await expect(replacement).not.toContainText('stale delayed response');
    });
});
