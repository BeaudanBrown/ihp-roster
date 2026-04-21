import { test, expect } from '@playwright/test';
import { gotoWhenReady } from './test-helpers';

const modalSelector = '#quarter-hour-time-picker-modal';

async function loginAndOpenRoster(page) {
    await gotoWhenReady(page, '/NewSession', '#email');
    await page.fill('#email', 'e2e-test@example.com');
    await page.fill('#password', 'test-password-123');
    await page.click('button[type="submit"]');

    await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/);
    await expect(page.locator('#roster-week-shell')).toBeVisible();

    for (let step = 0; step < 4; step += 1) {
        const createDraftButton = page.locator('button:has-text("Create Draft Roster")');
        if (await createDraftButton.isVisible()) {
            await createDraftButton.click();
            await expect(page.locator('#roster-week-shell')).toBeVisible();
        }

        const hasEditableRows = (await page.locator('select[name="staffId"]').count()) > 0;
        const hasAddRowControl = await page.locator('[data-roster-day-add="true"]').first().isVisible().catch(() => false);
        if (hasEditableRows || hasAddRowControl) {
            break;
        }

        await page.getByRole('link', { name: 'Next week' }).click();
        await expect(page.locator('#roster-week-shell')).toBeVisible();
    }

    await expect(page.locator('table.roster-grid')).toBeVisible();
    await expect(page.locator('[data-roster-day-add="true"]').first()).toBeVisible();

    const timeFields = page.locator('[data-time-picker-field]');
    if ((await timeFields.count()) === 0) {
        await page.locator('[data-roster-day-add="true"]').first().click();
        await expect(page.locator('[data-time-picker-field]').first()).toBeVisible();
    }
}

async function addFreshRowAndGetFirstTimeField(page) {
    const firstDaySection = page.locator('tbody[data-roster-day-section="true"]').first();
    const editableRows = firstDaySection.locator('tr[data-roster-row]').filter({ has: page.locator('select[name="staffId"]') });
    const initialRowCount = await editableRows.count();
    await page.locator('[data-roster-day-add="true"]').first().click();
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
