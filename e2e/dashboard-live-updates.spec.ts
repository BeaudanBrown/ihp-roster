import { test, expect } from '@playwright/test';
import { gotoWhenReady, loginAs, pauseLiveUpdates, resumeLiveUpdates, waitForLiveUpdatesReady } from './test-helpers';

const liveScope = 'dashboard-live-demo';

async function readLiveCount(page) {
    const text = await page.locator('#dashboard-live-demo-count').innerText();
    const match = text.match(/(\d+)/);
    if (!match) {
        throw new Error(`Could not parse live count from: ${text}`);
    }
    return Number(match[1]);
}

test.describe('Dashboard live updates', () => {
    test('increments via HTMX without full navigation and syncs across tabs', async ({ browser }) => {
        const context = await browser.newContext();
        const pageA = await context.newPage();
        const pageB = await context.newPage();

        await loginAs(pageA, 'e2e-test@example.com', 'test-password-123');
        await loginAs(pageB, 'e2e-test@example.com', 'test-password-123');
        await waitForLiveUpdatesReady(pageA, liveScope);
        await waitForLiveUpdatesReady(pageB, liveScope);

        const before = await readLiveCount(pageA);
        await pageA.evaluate(() => {
            window.__dashboardMarker = 'persisted-through-htmx';
        });

        await pageA.locator('button:has-text("Increment Live Demo")').click();

        await expect.poll(async () => readLiveCount(pageA)).toBe(before + 1);
        await expect.poll(async () => readLiveCount(pageB)).toBe(before + 1);
        await expect(pageA).toHaveURL(/Dashboard/);
        await expect(pageA.evaluate(() => window.__dashboardMarker)).resolves.toBe('persisted-through-htmx');

        await context.close();
    });

    test('defers external fragment refresh while a field inside the fragment is focused', async ({ browser }) => {
        const context = await browser.newContext();
        const pageA = await context.newPage();
        const pageB = await context.newPage();

        await loginAs(pageA, 'e2e-test@example.com', 'test-password-123');
        await loginAs(pageB, 'e2e-test@example.com', 'test-password-123');
        await waitForLiveUpdatesReady(pageA, liveScope);
        await waitForLiveUpdatesReady(pageB, liveScope);

        const before = await readLiveCount(pageA);
        const draftField = pageB.locator('#dashboard-live-demo-notes');

        await draftField.fill('unsaved draft while waiting for blur');
        await draftField.focus();
        expect(await pageB.evaluate(() => document.activeElement?.id)).toBe('dashboard-live-demo-notes');

        await pageA.locator('button:has-text("Increment Live Demo")').click();

        await expect.poll(async () => readLiveCount(pageA)).toBe(before + 1);
        await pageB.waitForTimeout(1200);
        expect(await readLiveCount(pageB)).toBe(before);

        await draftField.evaluate((element) => element.blur());
        await expect.poll(async () => readLiveCount(pageB)).toBe(before + 1);

        await context.close();
    });

    test('resyncs after the websocket reconnects', async ({ browser }) => {
        const context = await browser.newContext();
        const pageA = await context.newPage();
        const pageB = await context.newPage();

        await loginAs(pageA, 'e2e-test@example.com', 'test-password-123');
        await loginAs(pageB, 'e2e-test@example.com', 'test-password-123');
        await waitForLiveUpdatesReady(pageA, liveScope);
        await waitForLiveUpdatesReady(pageB, liveScope);

        const before = await readLiveCount(pageA);

        await pauseLiveUpdates(pageB);
        await pageA.locator('button:has-text("Increment Live Demo")').click();

        await expect.poll(async () => readLiveCount(pageA)).toBe(before + 1);
        await pageB.waitForTimeout(1200);
        expect(await readLiveCount(pageB)).toBe(before);

        await resumeLiveUpdates(pageB, liveScope);
        await expect.poll(async () => readLiveCount(pageB)).toBe(before + 1);

        await context.close();
    });

    test('rehydrates date and time picker controls inside an HTMX dialog', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Dashboard', '#dashboard-live-demo-fragment');

        await page.getByRole('button', { name: 'Open Runtime Dialog' }).click();

        const dialog = page.locator('[data-dialog-overlay="true"]');
        const dateInput = page.locator('#dashboard-runtime-demo-date');
        const timeField = page.locator('#dashboard-runtime-demo-time-field');
        const trigger = timeField.locator('.js-time-picker-trigger');
        const label = timeField.locator('.js-time-picker-label');
        const hiddenInput = timeField.locator('.js-time-picker-input');

        await expect(dialog).toBeVisible();
        await expect(dateInput).toBeVisible();
        await expect
            .poll(async () => dateInput.evaluate((input) => Boolean((input as HTMLInputElement & { _flatpickr?: unknown })._flatpickr)))
            .toBe(true);

        await trigger.click();
        await expect(page.locator('#quarter-hour-time-picker-modal')).toBeVisible();
        await page.locator('#quarter-hour-time-picker-modal .js-time-picker-option[data-time-value="13:15"]').click();

        await expect(page.locator('#quarter-hour-time-picker-modal')).toBeHidden();
        await expect(label).toHaveText('1:15 PM');
        await expect(hiddenInput).toHaveValue('13:15');

        await dialog.getByLabel('Close').click();
        await expect(page.locator('#dialog-overlay-mount')).toBeEmpty();
    });
});
