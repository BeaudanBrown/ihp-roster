import { test, expect, type Page } from '@playwright/test';
import { openRoster } from './test-helpers';

async function loginAndOpenRoster(page: Page) {
    await openRoster(page, { email: 'e2e-test@example.com' });
    await expect(page.locator('.roster-staff-panel')).toBeVisible();
}

test.describe('Roster Staff Modal', () => {
    test('edits staff inline without navigating away from the roster', async ({ page }) => {
        await loginAndOpenRoster(page);

        const initialUrl = page.url();
        const modalMount = page.locator('#dialog-overlay-mount');
        const staffEntry = page.locator('.roster-staff-panel-entry:visible').first();
        const nameLabel = staffEntry.locator('.roster-staff-name-primary');
        const originalName = (await nameLabel.textContent())?.trim() || 'E2E Manager';
        const updatedName = 'Roster Modal Spec';

        await staffEntry.click();

        await expect(page).toHaveURL(initialUrl);
        await expect(modalMount.locator('[data-dialog-overlay="true"]')).toBeVisible();
        await expect(modalMount).toContainText('Edit Staff Member');
        await modalMount.getByRole('button', { name: 'Profile Details' }).click();

        const staffEditForm = modalMount.locator('#staff-edit-form:visible');
        await expect(staffEditForm).toBeVisible();
        const firstNameField = staffEditForm.locator('#firstName');
        const lastNameField = staffEditForm.locator('#lastName');
        const formAction = await staffEditForm.getAttribute('action');
        const weekOffset = await staffEditForm.locator('input[name="weekOffset"]').inputValue();

        const validationResponse = await page.evaluate(
            async ({ action, currentWeekOffset }) => {
                const response = await fetch(action, {
                    method: 'POST',
                    headers: {
                        'HX-Request': 'true',
                        'Content-Type': 'application/x-www-form-urlencoded',
                    },
                    body: new URLSearchParams({
                        weekOffset: currentWeekOffset,
                        firstName: '',
                        lastName: 'User',
                        idealShiftsPerWeek: '4',
                        isActive: 'on',
                    }).toString(),
                });

                return await response.text();
            },
            { action: formAction ?? '', currentWeekOffset: weekOffset },
        );

        expect(validationResponse).toContain('Edit Staff Member');
        expect(validationResponse).toContain('This field cannot be empty');
        expect(validationResponse).not.toContain('Roster App');

        await firstNameField.fill('Roster');
        await lastNameField.fill('Modal Spec');
        await modalMount.getByRole('button', { name: 'Save' }).click();

        await expect(page).toHaveURL(initialUrl);
        await expect(modalMount).toBeEmpty();

    });
});
