import { test, expect } from '@playwright/test';
import {
    dialogOverlayMountDomId,
    timePickerClearDomAttr,
    timePickerTriggerDomAttr,
    toggleInputDomAttr,
} from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT, gotoWhenReady, loginAs } from './test-helpers';

test.describe('Workflow dialog keyboard controls', () => {
    test.setTimeout(E2E_TIMEOUT.test);

    test('keeps Timesheet tabbing in visual order while starting on Shift Start', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');
        await page.locator('[data-timesheet-day-add="true"]').first().click();

        const dialogMount = page.locator(`#${dialogOverlayMountDomId}`);
        const form = dialogMount.locator('#timesheet-entry-create-form');
        await expect(form).toBeVisible({ timeout: E2E_TIMEOUT.action });

        const startTrigger = form.locator(`[${timePickerTriggerDomAttr}]`).nth(0);
        const endTrigger = form.locator(`[${timePickerTriggerDomAttr}]`).nth(1);
        const hadBreak = form.locator(`[${toggleInputDomAttr}]`);
        await expect(startTrigger).toBeFocused();

        await page.keyboard.press('Shift+Tab');
        await expect(form.locator('#shiftTypeId')).toBeFocused();
        await startTrigger.focus();
        await page.keyboard.press('Tab');
        await expect(endTrigger).toBeFocused();
        await page.keyboard.press('Tab');
        await expect(hadBreak).toBeFocused();

        await page.keyboard.press('Space');
        await expect(hadBreak).toBeChecked();
        const breakDurationTrigger = form.locator(`[${timePickerTriggerDomAttr}]`).nth(2);
        await expect(breakDurationTrigger).toBeVisible();
        await expect(breakDurationTrigger).toBeEnabled();
        await page.keyboard.press('Tab');
        await expect(breakDurationTrigger).toBeFocused();

        const staffComment = form.locator('#staffComment');
        if (await staffComment.count() > 0) {
            await staffComment.focus();
            await page.keyboard.type('First line');
            await page.keyboard.press('Enter');
            await page.keyboard.type('Second line');
            await expect(staffComment).toHaveValue('First line\nSecond line');
            await expect(form).toBeVisible();
        }

        await hadBreak.focus();
        await page.keyboard.press('Space');
        await expect(hadBreak).not.toBeChecked();

        const saveResponse = page.waitForResponse((response) =>
            response.request().method() === 'POST' && response.url().includes('/CreateTimesheetEntry'),
        );
        await form.locator('#shiftTypeId').focus();
        await page.keyboard.press('Enter');
        expect((await saveResponse).status()).toBe(200);
        await expect(dialogMount).toBeEmpty({ timeout: E2E_TIMEOUT.liveUpdate });
    });

    test('focuses the first invalid field after an HTMX validation replacement', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');
        await page.locator('[data-timesheet-day-add="true"]').first().click();

        const dialogMount = page.locator(`#${dialogOverlayMountDomId}`);
        const form = dialogMount.locator('#timesheet-entry-create-form');
        const startTrigger = form.locator(`[${timePickerTriggerDomAttr}]`).first();
        await expect(startTrigger).toBeFocused();
        await startTrigger.click();
        await page.locator(`[${timePickerClearDomAttr}]`).click();

        const validationResponse = page.waitForResponse((response) =>
            response.request().method() === 'POST' && response.url().includes('/CreateTimesheetEntry'),
        );
        await form.locator('#shiftTypeId').focus();
        await page.keyboard.press('Enter');
        expect((await validationResponse).status()).toBe(200);

        const invalidStart = dialogMount.locator('#timesheet-entry-create-form').locator(`[${timePickerTriggerDomAttr}]`).first();
        await expect(invalidStart).toHaveAttribute('aria-invalid', 'true');
        await expect(invalidStart).toBeFocused();
        await page.keyboard.press('Escape');
        await expect(dialogMount).toBeEmpty({ timeout: E2E_TIMEOUT.action });
    });
});
