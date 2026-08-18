import { test, expect } from '@playwright/test';
import {
    orderedRangeAvailabilityDomAttr,
    orderedRangeRootDomAttr,
    orderedRangeStartDomAttr,
} from '../frontend/ts/generated/contracts';
import { gotoWhenReady, loginAs } from './test-helpers';
import { E2E_TIMEOUT } from './timeouts';

test.describe('Shift preference autosave', () => {
    test('saves a completed mobile range adjustment without a submit button @canonical-mobile', async ({ page }) => {
        await page.setViewportSize({ width: 393, height: 851 });
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await gotoWhenReady(page, '/EditProfile?section=preferences', '#profile-content-fragment');

        const preferencesToggle = page.getByRole('button', { name: 'Shift Preferences', exact: true });
        if ((await preferencesToggle.getAttribute('aria-expanded')) !== 'true') {
            await preferencesToggle.click();
        }

        const form = page.locator('#profile-shift-preferences-form');
        await expect(form).toHaveAttribute('hx-trigger', 'change');
        await expect(form).toHaveAttribute('hx-sync', 'this:queue last');
        await expect(form.locator('button[type="submit"]')).toHaveCount(0);

        const firstRange = page.locator(`[${orderedRangeRootDomAttr}]`).first();
        const availability = firstRange.locator(`[${orderedRangeAvailabilityDomAttr}] label`);
        let start = firstRange.locator(`[${orderedRangeStartDomAttr}]`);
        if (await start.isDisabled()) {
            const swapPromise = page.evaluate(() => new Promise<void>((resolve) => {
                document.addEventListener('htmx:afterSwap', () => resolve(), { once: true });
            }));
            await Promise.all([
                page.waitForResponse((response) => response.url().includes('/UpdateProfile') && response.request().method() === 'POST'),
                availability.click(),
                swapPromise,
            ]);
            await expect(start).toBeEnabled({ timeout: E2E_TIMEOUT.liveUpdate });
        }

        await expect(start).toHaveCSS('height', '32px');
        const name = await start.getAttribute('name');
        if (name === null) throw new Error('Expected a named preference start range');

        const requestPromise = page.waitForRequest((request) => (
            request.url().includes('/UpdateProfile') && request.method() === 'POST'
        ));
        await start.evaluate((element) => {
            if (!(element instanceof HTMLInputElement)) throw new Error('Expected a range input');
            element.value = element.min;
            element.dispatchEvent(new Event('input', { bubbles: true }));
            element.dispatchEvent(new Event('change', { bubbles: true }));
        });
        const request = await requestPromise;
        expect(new URLSearchParams(request.postData() ?? '').get(name)).toBe(await start.getAttribute('min'));
    });
});
