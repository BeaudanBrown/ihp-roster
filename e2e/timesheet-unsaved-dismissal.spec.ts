import { expect, test, type Page } from '@playwright/test';
import {
    dialogBackdropDomAttr,
    dialogCloseDomAttr,
    dialogOverlayMountDomId,
    timePickerClearDomAttr,
    timePickerTriggerDomAttr,
} from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady } from './support/runtime';
import { loginAs } from './support/session';

const mountSelector = `#${dialogOverlayMountDomId}`;

async function openNewTimesheet(page: Page) {
    await page.locator('[data-timesheet-day-add="true"]').first().click();
    await expect(page.locator('#timesheet-entry-create-form')).toBeVisible({ timeout: E2E_TIMEOUT.action });
}

async function attemptClose(page: Page) {
    await page.locator(`${mountSelector} [${dialogCloseDomAttr}]`).first().click();
}

async function beforeUnloadIsGuarded(page: Page) {
    return await page.evaluate(() => {
        const event = new Event('beforeunload', { cancelable: true });
        return !window.dispatchEvent(event) && event.defaultPrevented;
    });
}

test.describe('Timesheet unsaved dismissal guard', () => {
    test.beforeEach(async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');
    });

    test('new Timesheets retain values until explicit discard across every dismissal path', async ({ page }) => {
        await openNewTimesheet(page);
        const form = page.locator('#timesheet-entry-create-form');
        const comment = form.locator('textarea').first();
        if (await comment.count()) await comment.fill('Retain this unsaved value');
        expect(await beforeUnloadIsGuarded(page)).toBe(true);

        await attemptClose(page);
        const confirmationTitle = page.getByRole('heading', { name: 'Discard unsaved timesheet?' });
        const keepEditing = page.getByRole('button', { name: 'Keep editing' });
        const discardTimesheet = page.getByRole('button', { name: 'Discard timesheet' });
        await expect(confirmationTitle).toBeVisible();
        await expect(page.getByRole('dialog')).toHaveAttribute('aria-labelledby', 'dialog-overlay-confirmation-title');
        await expect(keepEditing).toBeFocused();
        await page.keyboard.press('Tab');
        await expect(discardTimesheet).toBeFocused();
        await page.keyboard.press('Shift+Tab');
        await expect(keepEditing).toBeFocused();
        await page.keyboard.press('Enter');
        await expect(form).toBeVisible();

        await attemptClose(page);
        await page.keyboard.press('Escape');
        await expect(form).toBeVisible();
        await expect(page.locator(`${mountSelector} [${dialogCloseDomAttr}]`).first()).toBeFocused();
        if (await comment.count()) await expect(comment).toHaveValue('Retain this unsaved value');

        await page.locator(`[${dialogBackdropDomAttr}]`).dispatchEvent('click');
        await expect(page.getByRole('heading', { name: 'Discard unsaved timesheet?' })).toBeVisible();
        await page.getByRole('button', { name: 'Close' }).click();
        await expect(form).toBeVisible();

        await page.getByRole('button', { name: 'Cancel' }).click();
        await expect(page.getByRole('heading', { name: 'Discard unsaved timesheet?' })).toBeVisible();
        await page.getByRole('button', { name: 'Keep editing' }).click();
        await expect(form).toBeVisible();

        await attemptClose(page);
        await page.getByRole('button', { name: 'Discard timesheet' }).click();
        await expect(page.locator(mountSelector)).toBeEmpty({ timeout: E2E_TIMEOUT.action });
        expect(await beforeUnloadIsGuarded(page)).toBe(false);

        await openNewTimesheet(page);
        await page.getByRole('button', { name: 'Save' }).click();
        await expect(page.locator(mountSelector)).toBeEmpty({ timeout: E2E_TIMEOUT.action });
        expect(await beforeUnloadIsGuarded(page)).toBe(false);
    });

    test('edit guards normalized changes, survives invalid replacement, reversion, and bypasses delete', async ({ page }) => {
        const card = page.locator('.timesheet-entry-card').filter({ has: page.locator('.timesheet-entry-card-link') }).first();
        await card.locator('.timesheet-entry-card-link').click();
        let form = page.locator('#timesheet-entry-edit-form');
        await expect(form).toBeVisible({ timeout: E2E_TIMEOUT.action });

        await attemptClose(page);
        await expect(page.locator(mountSelector)).toBeEmpty({ timeout: E2E_TIMEOUT.action });

        await card.locator('.timesheet-entry-card-link').click();
        form = page.locator('#timesheet-entry-edit-form');
        const editable = form.locator('textarea').first();
        const openingValue = await editable.inputValue();
        await editable.fill(`${openingValue} changed`);
        expect(await beforeUnloadIsGuarded(page)).toBe(true);
        await attemptClose(page);
        await expect(page.getByRole('heading', { name: 'Discard unsaved changes?' })).toBeVisible();
        await page.getByRole('button', { name: 'Keep editing' }).click();
        await expect(editable).toHaveValue(`${openingValue} changed`);
        await editable.fill(openingValue);
        await attemptClose(page);
        await expect(page.locator(mountSelector)).toBeEmpty({ timeout: E2E_TIMEOUT.action });

        await openNewTimesheet(page);
        form = page.locator('#timesheet-entry-create-form');
        await form.locator(`[${timePickerTriggerDomAttr}]`).first().click();
        await page.locator(`[${timePickerClearDomAttr}]`).click();
        await page.getByRole('button', { name: 'Save' }).click();
        form = page.locator('#timesheet-entry-create-form');
        await expect(form.locator(`[${timePickerTriggerDomAttr}]`).first()).toHaveAttribute('aria-invalid', 'true');
        await attemptClose(page);
        await expect(page.getByRole('heading', { name: 'Discard unsaved timesheet?' })).toBeVisible();
        await page.getByRole('button', { name: 'Keep editing' }).click();
        await expect(form.locator(`[${timePickerTriggerDomAttr}]`).first()).toHaveAttribute('aria-invalid', 'true');
        await attemptClose(page);
        await page.getByRole('button', { name: 'Discard timesheet' }).click();

        await card.locator('.timesheet-entry-card-link').click();
        form = page.locator('#timesheet-entry-edit-form');
        await form.locator('textarea').first().fill('delete bypass change');
        await page.getByRole('button', { name: 'Delete' }).click();
        await expect(page.getByRole('heading', { name: 'Delete timesheet entry?' })).toBeVisible();
        await expect(page.getByRole('heading', { name: 'Discard unsaved changes?' })).toHaveCount(0);
        expect(await beforeUnloadIsGuarded(page)).toBe(false);
    });
});
