import { test, expect } from '@playwright/test';

const modalSelector = '#quarter-hour-time-picker-modal';

async function loginAndOpenRoster(page) {
    await page.goto('/NewSession');
    await page.fill('#email', 'e2e-test@example.com');
    await page.fill('#password', 'test-password-123');
    await page.click('button[type="submit"]');

    await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/);

    const createDraftButton = page.locator('button:has-text("Create Draft Roster")');
    if (await createDraftButton.isVisible()) {
        await createDraftButton.click();
    }

    await expect(page.locator('table.roster-grid')).toBeVisible();

    const timeFields = page.locator('[data-time-picker-field]');
    if ((await timeFields.count()) === 0) {
        await page.locator('button[title="Add shift row"]').first().click();
        await expect(page.locator('[data-time-picker-field]').first()).toBeVisible();
    }
}

async function addFreshRowAndGetFirstTimeField(page) {
    const firstDaySection = page.locator('tbody[data-roster-day-section="true"]').first();
    const initialRowCount = await firstDaySection.locator('tr[data-roster-row]').count();
    await page.locator('button[title="Add shift row"]').first().click();
    await expect(firstDaySection.locator('tr[data-roster-row]')).toHaveCount(initialRowCount + 1);
    const firstField = firstDaySection.locator('tr[data-roster-row]').last().locator('[data-time-picker-field]').first();
    await expect(firstField.locator('.js-time-picker-label')).toHaveText('Select time');
    await expect(firstField.locator('.js-time-picker-input')).toHaveValue('');
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
        await expect(label).toHaveCount(1);
        await expect(hiddenInput).toHaveCount(1);

        const initErrors = pageErrors.filter((message) =>
            message.includes("Cannot read properties of null (reading 'addEventListener')")
        );
        expect(initErrors).toHaveLength(0);
    });

    test('clear action resets the selected time', async ({ page }) => {
        await loginAndOpenRoster(page);

        const firstField = await addFreshRowAndGetFirstTimeField(page);
        const trigger = firstField.locator('.js-time-picker-trigger');
        const label = firstField.locator('.js-time-picker-label');
        const hiddenInput = firstField.locator('.js-time-picker-input');

        await trigger.click();
        await page.locator(`${modalSelector} .js-time-picker-option[data-time-value="06:30"]`).click();
        await expect(page.locator(modalSelector)).toBeHidden();
        await expect(label).toHaveCount(1);
        await expect(hiddenInput).toHaveCount(1);

        await trigger.click();
        await page.locator(`${modalSelector} .js-time-picker-clear`).click();

        await expect(page.locator(modalSelector)).toBeHidden();
        await expect(label).toHaveCount(1);
        await expect(hiddenInput).toHaveCount(1);
    });
});
