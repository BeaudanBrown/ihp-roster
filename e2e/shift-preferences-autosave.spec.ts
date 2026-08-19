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
        const preferencesTargetSelector = await form.getAttribute('hx-target');
        if (preferencesTargetSelector === null) throw new Error('Expected a shift-preferences HTMX target');
        const capturePreferencesTarget = async () => {
            const target = await page.locator(preferencesTargetSelector).elementHandle();
            if (target === null) throw new Error('Expected a mounted shift-preferences target');
            return target;
        };
        const expectPreferencesTargetReplaced = (target: Awaited<ReturnType<typeof capturePreferencesTarget>>) =>
            expect.poll(
                () => target.evaluate((element) => element.isConnected),
                { timeout: E2E_TIMEOUT.liveUpdate },
            ).toBe(false);

        const firstRange = page.locator(`[${orderedRangeRootDomAttr}]`).first();
        const availability = firstRange.locator(`[${orderedRangeAvailabilityDomAttr}] label`);
        let start = firstRange.locator(`[${orderedRangeStartDomAttr}]`);
        if (await start.isDisabled()) {
            const previousPreferencesTarget = await capturePreferencesTarget();
            const [response] = await Promise.all([
                page.waitForResponse((candidate) => candidate.url().includes('/UpdateProfile') && candidate.request().method() === 'POST'),
                availability.click(),
            ]);
            await response.finished();
            await expectPreferencesTargetReplaced(previousPreferencesTarget);
            await expect(start).toBeEnabled({ timeout: E2E_TIMEOUT.liveUpdate });
        }

        await expect(start).toHaveCSS('height', '32px');
        const name = await start.getAttribute('name');
        if (name === null) throw new Error('Expected a named preference start range');

        const minimumValue = await start.getAttribute('min');
        const maximumValue = await start.getAttribute('max');
        if (minimumValue === null || maximumValue === null) throw new Error('Expected bounded preference values');
        const currentValue = await start.inputValue();
        const expectedValue = currentValue === minimumValue ? maximumValue : minimumValue;
        const adjustmentKey = currentValue === minimumValue ? 'End' : 'Home';
        const previousPreferencesTarget = await capturePreferencesTarget();
        await start.focus();
        const [request, response] = await Promise.all([
            page.waitForRequest((candidate) => candidate.url().includes('/UpdateProfile') && candidate.method() === 'POST'),
            page.waitForResponse((candidate) => candidate.url().includes('/UpdateProfile') && candidate.request().method() === 'POST'),
            start.press(adjustmentKey),
        ]);
        expect(response.status(), await response.text()).toBe(200);
        await response.finished();
        await expectPreferencesTargetReplaced(previousPreferencesTarget);
        expect(new URLSearchParams(request.postData() ?? '').get(name)).toBe(expectedValue);
        await expect(start).toHaveValue(expectedValue);
    });
});
