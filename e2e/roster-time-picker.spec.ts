import { test, expect, type Locator, type Page } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { addRowToRosterDay, editableRosterRows, firstEditableRosterDaySection, openRoster, openRosterShiftDialog } from './test-helpers';

const modalSelector = '#quarter-hour-time-picker-modal';

async function loginAndOpenRoster(page: Page) {
    await openRoster(page);
}

async function chooseTime(page: Page, value: string) {
    await page.locator(`${modalSelector} .js-time-picker-option[data-time-value="${value}"]`).click();
}

async function addFreshRowAndGetFirstTimeField(page: Page): Promise<Locator> {
    const firstDaySection = firstEditableRosterDaySection(page);
    const editableRows = editableRosterRows(firstDaySection);
    const initialRowCount = await editableRows.count();
    await addRowToRosterDay(firstDaySection);
    await expect(editableRows).toHaveCount(initialRowCount + 1);
    const launcher = editableRows.last().locator('[data-roster-shift-launcher="true"]').first();
    await openRosterShiftDialog(page, launcher);
    const firstField = page.locator('#dialog-overlay-mount [data-time-picker-field]').first();
    await expect(firstField.locator('.js-time-picker-label')).toHaveText('6:00 AM');
    await expect(firstField.locator('.js-time-picker-input')).toHaveValue('06:00');
    return firstField;
}

test.describe('Roster Time Picker', () => {
    test.setTimeout(E2E_TIMEOUT.slowTest);

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
        await expect(page.locator(`${modalSelector} .js-time-picker-option`)).toHaveCount(96);
        await expect(page.locator(`${modalSelector} .js-time-picker-option[data-time-value="05:45"]`)).toBeVisible();

        await chooseTime(page, '13:15');

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
        await chooseTime(page, '06:30');
        await expect(modal).toBeHidden();
        await expect(firstField.locator('.js-time-picker-label')).toHaveText('6:30 AM');
        await expect(firstField.locator('.js-time-picker-input')).toHaveValue('06:30');

        await trigger.click();
        await expect(modal).toBeVisible();
        await expect(clearButton).toBeVisible();
        await clearButton.click();

        await expect(modal).toBeHidden();
        await expect(firstField.locator('.js-time-picker-label')).toHaveText('Start');
        await expect(firstField.locator('.js-time-picker-input')).toHaveValue('');
    });
});
