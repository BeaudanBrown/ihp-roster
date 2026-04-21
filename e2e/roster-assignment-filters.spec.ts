import { test, expect, Locator } from '@playwright/test';
import {
    addRowToRosterDay,
    editableRosterRows,
    firstEditableRosterDaySection,
    openRoster,
} from './test-helpers';

async function loginAndOpenRoster(page) {
    await openRoster(page, { weekOffset: 1 });
}

async function optionValues(select: Locator) {
    return await select.locator('option').evaluateAll((options) =>
        options
            .map((option) => (option instanceof HTMLOptionElement ? option.value : ''))
            .filter((value) => value !== ''),
    );
}

test.describe('Roster assignment filters', () => {
    test('updates other staff dropdowns immediately when already-assigned-today filtering is active', async ({ page }) => {
        await loginAndOpenRoster(page);

        await page.getByLabel('Roster actions').click();
        await page.getByLabel('Already assigned that day').check();
        await expect(page.locator('#roster-content')).toBeVisible();

        const daySection = firstEditableRosterDaySection(page);
        let rows = editableRosterRows(daySection);
        if ((await rows.count()) < 2) {
            await addRowToRosterDay(daySection);
            await expect
                .poll(async () => await editableRosterRows(page).count())
                .toBe(2);
            rows = editableRosterRows(firstEditableRosterDaySection(page));
        }
        expect(await rows.count()).toBeGreaterThanOrEqual(2);

        const firstRowSelect = rows.nth(0).locator('select[name="staffId"]').first();
        const secondRowSelect = rows.nth(1).locator('select[name="staffId"]').first();

        const firstRowValue = await firstRowSelect.inputValue();
        const secondRowValue = await secondRowSelect.inputValue();
        const secondRowOptionValues = await optionValues(secondRowSelect);
        const candidateValue = secondRowOptionValues.find(
            (value) => value !== firstRowValue && value !== secondRowValue,
        );

        expect(candidateValue).toBeTruthy();

        await expect
            .poll(async () => {
                const values = await optionValues(secondRowSelect);
                return values.includes(candidateValue!);
            })
            .toBe(true);

        await firstRowSelect.selectOption(candidateValue!);
        await expect(firstRowSelect).toHaveValue(candidateValue!);

        await expect
            .poll(async () => {
                const values = await optionValues(secondRowSelect);
                return values.includes(candidateValue!);
            })
            .toBe(false);
    });

});
