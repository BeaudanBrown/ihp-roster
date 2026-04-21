import { test, expect } from '@playwright/test';
import { addRowToFirstRosterDay, editableRosterRows, openRoster } from './test-helpers';

const modalSelector = '#quarter-hour-time-picker-modal';

async function loginAndOpenRoster(page) {
    await openRoster(page);

    if ((await page.locator('[data-time-picker-field]').count()) === 0) {
        await addRowToFirstRosterDay(page);
        await expect(page.locator('[data-time-picker-field]').first()).toBeVisible();
    }
}

async function addFreshRowAndGetFirstTimeField(page) {
    const firstDaySection = page.locator('tbody[data-roster-day-section="true"]').first();
    const editableRows = editableRosterRows(firstDaySection);
    const initialRowCount = await editableRows.count();
    await addRowToFirstRosterDay(page);
    await expect(editableRows).toHaveCount(initialRowCount + 1);
    const firstField = editableRows.last().locator('[data-time-picker-field]').first();
    await expect(firstField.locator('.js-time-picker-label')).toHaveText('Time');
    await expect(firstField.locator('.js-time-picker-input')).toHaveValue('');
    await expect(firstField.locator('.js-time-picker-step-down')).toHaveCount(0);
    await expect(firstField.locator('.js-time-picker-step-up')).toHaveCount(0);
    return firstField;
}

test.describe('Roster Time Picker', () => {
    test.setTimeout(120000);

    test('opens modal picker and selects a time', async ({ page }) => {
        const pageErrors: string[] = [];
        page.on('pageerror', (error) => {
            pageErrors.push(error.message);
        });

        await loginAndOpenRoster(page);

        const firstField = await addFreshRowAndGetFirstTimeField(page);
        const trigger = firstField.locator('.js-time-picker-trigger');
        const label = firstField.locator('.js-time-picker-label');
        const hiddenInput = firstField.locator('.js-time-picker-input');

        await trigger.click();
        await expect(page.locator(modalSelector)).toBeVisible();
        await expect(page.locator(`${modalSelector} .js-time-picker-option`)).toHaveCount(72);

        await page.locator(`${modalSelector} .js-time-picker-option[data-time-value="13:15"]`).click();

        await expect(page.locator(modalSelector)).toBeHidden();
        await expect(firstField.locator('.js-time-picker-label')).toHaveText('1:15 PM');
        await expect(firstField.locator('.js-time-picker-input')).toHaveValue('13:15');

        const initErrors = pageErrors.filter((message) =>
            message.includes("Cannot read properties of null (reading 'addEventListener')")
        );
        expect(initErrors).toHaveLength(0);
    });

    test('clear action resets the selected time', async ({ page }) => {
        await loginAndOpenRoster(page);

        const firstField = await addFreshRowAndGetFirstTimeField(page);
        const trigger = firstField.locator('.js-time-picker-trigger');
        const modal = page.locator(modalSelector);
        const clearButton = page.locator(`${modalSelector} .js-time-picker-clear`);

        await trigger.click();
        await page.locator(`${modalSelector} .js-time-picker-option[data-time-value="06:30"]`).click();
        await expect(modal).toBeHidden();
        await expect(firstField.locator('.js-time-picker-label')).toHaveText('6:30 AM');
        await expect(firstField.locator('.js-time-picker-input')).toHaveValue('06:30');

        await trigger.click();
        await expect(modal).toBeVisible();
        await expect(clearButton).toBeVisible();
        await clearButton.click();

        await expect(modal).toBeHidden();
        await expect(firstField.locator('.js-time-picker-label')).toHaveText('Time');
        await expect(firstField.locator('.js-time-picker-input')).toHaveValue('');
    });
});
