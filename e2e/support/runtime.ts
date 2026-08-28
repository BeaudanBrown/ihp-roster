import { expect, type Page, type Request } from '@playwright/test';
import { surfaceConfigDomAttr } from '../../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from '../timeouts';

let uniqueE2ECounter = 0;

export function uniqueE2EValue(prefix: string) {
    uniqueE2ECounter += 1;
    const runId = (process.env.E2E_RUN_ID ?? `pid-${process.pid}`).replace(/[^a-zA-Z0-9-]/g, '-');
    return `${prefix}-${runId}-${uniqueE2ECounter}`;
}

export async function runActionUntilRequestStarts(
    page: Page,
    isExpectedRequest: (request: Request) => boolean,
    action: () => Promise<void>,
) {
    const responsePromise = page.waitForResponse((response) => isExpectedRequest(response.request()));
    // Retry only while the browser/runtime declines the action. Once a request
    // starts, return its one response and never repeat the mutation.
    await expect(async () => {
        const requestPromise = page.waitForRequest(isExpectedRequest, { timeout: E2E_TIMEOUT.quick });
        await action();
        await requestPromise;
    }).toPass({ timeout: E2E_TIMEOUT.action });
    return await responsePromise;
}

type LiveRecoveryTrackerWindow = Window & {
    __bepisE2ELiveRecovery?: {
        installed: boolean;
        addedScopeKeys: string[];
        acknowledgedScopeKeys: string[];
        activeHtmxRequests: number;
        lastHtmxActivityAt: number;
    };
};

async function installLiveRecoveryTracker(page: Page) {
    await page.addInitScript(() => {
        const state = window as LiveRecoveryTrackerWindow;
        if (state.__bepisE2ELiveRecovery?.installed) return;
        state.__bepisE2ELiveRecovery = {
            installed: true,
            addedScopeKeys: [],
            acknowledgedScopeKeys: [],
            activeHtmxRequests: 0,
            lastHtmxActivityAt: performance.now(),
        };
        document.addEventListener('htmx:beforeRequest', () => {
            const tracker = state.__bepisE2ELiveRecovery;
            if (!tracker) return;
            tracker.activeHtmxRequests += 1;
            tracker.lastHtmxActivityAt = performance.now();
        });
        document.addEventListener('htmx:afterRequest', () => {
            const tracker = state.__bepisE2ELiveRecovery;
            if (!tracker) return;
            tracker.activeHtmxRequests = Math.max(0, tracker.activeHtmxRequests - 1);
            tracker.lastHtmxActivityAt = performance.now();
        });
        document.addEventListener('app:live-update-debug', (event) => {
            const detail = (event as CustomEvent).detail;
            if (typeof detail?.scopeKey !== 'string') return;
            if (detail.name === 'subscription_added') state.__bepisE2ELiveRecovery?.addedScopeKeys.push(detail.scopeKey);
            if (detail.name === 'subscription_acknowledged') state.__bepisE2ELiveRecovery?.acknowledgedScopeKeys.push(detail.scopeKey);
        });
    });
}

export async function waitForLiveRecovery(page: Page, timeoutMs = E2E_TIMEOUT.navigation) {
    const expectedScopeKeys = await page.locator(`[${surfaceConfigDomAttr}]`).evaluateAll((elements, configAttribute) =>
        Array.from(new Set(elements.flatMap((element) => {
            const rawConfig = element.getAttribute(configAttribute);
            if (!rawConfig) return [];
            try {
                const config = JSON.parse(rawConfig);
                return config.subscription && typeof config.scopeKey === 'string' ? [config.scopeKey] : [];
            } catch {
                return [];
            }
        }))), surfaceConfigDomAttr);
    if (expectedScopeKeys.length === 0) return;

    await expect.poll(() => page.evaluate((scopeKeys) => {
        const tracker = (window as LiveRecoveryTrackerWindow).__bepisE2ELiveRecovery;
        return Boolean(
            tracker
            && scopeKeys.every((scopeKey) => tracker.acknowledgedScopeKeys.includes(scopeKey))
            && tracker.activeHtmxRequests === 0
            && performance.now() - tracker.lastHtmxActivityAt >= 100
        );
    }, expectedScopeKeys), { timeout: timeoutMs }).toBe(true);
}

export async function gotoWhenReady(page: Page, path: string, readySelector: string, timeoutMs = E2E_TIMEOUT.navigation) {
    await installLiveRecoveryTracker(page);
    const deadline = Date.now() + timeoutMs;
    let lastBodyText = '';
    let lastNavigationError = '';

    while (Date.now() < deadline) {
        try {
            await page.goto(path);
        } catch (error) {
            lastNavigationError = error instanceof Error ? error.message : String(error);
            await page.waitForTimeout(E2E_TIMEOUT.quick);
            continue;
        }

        try {
            await page.locator(readySelector).waitFor({ state: 'visible', timeout: E2E_TIMEOUT.action });
            // Durable subscriptions can authoritatively resync immediately after
            // the server-rendered shell appears. Wait for the acknowledgement and
            // resulting fragment fetches before callers capture locators.
            await waitForLiveRecovery(page, timeoutMs);
            return;
        } catch {
            lastBodyText = (await page.locator('body').textContent().catch(() => '')) ?? '';

            const isTransientStartupPage =
                lastBodyText.includes('Is compiling')
                || lastBodyText.includes('ERR_CONNECTION_REFUSED')
                || lastBodyText.includes('refused to connect');

            if (!isTransientStartupPage) {
                break;
            }
        }

        await page.waitForTimeout(E2E_TIMEOUT.quick);
    }

    const failureContext = [lastBodyText, lastNavigationError].filter(Boolean).join('\n\n');
    await expect(page.locator(readySelector), failureContext).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
    await waitForLiveRecovery(page, timeoutMs);
}
