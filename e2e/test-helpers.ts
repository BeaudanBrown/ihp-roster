import { expect, Page } from '@playwright/test';

declare global {
    interface Window {
        appLiveUpdatesDebug?: {
            pause: () => string;
            resume: () => string;
            connectionState: () => string;
            subscribedScopes: () => string[];
        };
    }
}

export async function gotoWhenReady(page: Page, path: string, readySelector: string, timeoutMs = 60000) {
    const deadline = Date.now() + timeoutMs;
    let lastBodyText = '';
    let lastNavigationError = '';

    while (Date.now() < deadline) {
        try {
            await page.goto(path);
        } catch (error) {
            lastNavigationError = error instanceof Error ? error.message : String(error);
            await page.waitForTimeout(1000);
            continue;
        }

        try {
            await page.locator(readySelector).waitFor({ state: 'visible', timeout: 2000 });
            return;
        } catch {
            lastBodyText = (await page.locator('body').textContent().catch(() => '')) ?? '';

            if (!lastBodyText.includes('Is compiling')) {
                break;
            }
        }

        await page.waitForTimeout(1000);
    }

    const failureContext = [lastBodyText, lastNavigationError].filter(Boolean).join('\n\n');
    if (page.isClosed()) {
        throw new Error(`Page closed before ${readySelector} became visible.\n\n${failureContext}`);
    }
    await expect(page.locator(readySelector), failureContext).toBeVisible({ timeout: 5000 });
}

export async function loginAs(page: Page, email: string, password: string) {
    await gotoWhenReady(page, '/NewSession', '#email, #dashboard-live-demo-fragment');

    const emailField = page.locator('#email');
    if (await emailField.isVisible().catch(() => false)) {
        await emailField.fill(email);
        await page.fill('#password', password);
        await page.click('button[type="submit"]');
    }

    await expect(page).toHaveURL(/Dashboard/, { timeout: 60000 });
    await expect(page.locator('#dashboard-live-demo-fragment')).toBeVisible({ timeout: 60000 });
}

export async function waitForLiveUpdatesReady(page: Page, scope = 'dashboard-live-demo') {
    await expect
        .poll(
            async () =>
                page.evaluate((currentScope) => {
                    const debugApi = window.appLiveUpdatesDebug;
                    if (!debugApi) return 'missing';
                    if (!debugApi.subscribedScopes().includes(currentScope)) return 'missing-scope';
                    return debugApi.connectionState();
                }, scope),
            { message: `expected live updates to subscribe to ${scope}` },
        )
        .toBe('open');
}

export async function pauseLiveUpdates(page: Page) {
    await waitForLiveUpdatesReady(page);
    await page.evaluate(() => window.appLiveUpdatesDebug?.pause());
    await expect.poll(async () => page.evaluate(() => window.appLiveUpdatesDebug?.connectionState() ?? 'missing')).toBe('paused');
}

export async function resumeLiveUpdates(page: Page, scope = 'dashboard-live-demo') {
    await page.evaluate(() => window.appLiveUpdatesDebug?.resume());
    await waitForLiveUpdatesReady(page, scope);
}
