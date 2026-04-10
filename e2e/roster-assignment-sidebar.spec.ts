import { test, expect } from '@playwright/test';

async function loginAndOpenRoster(page) {
    await page.goto('/NewSession');
    await page.fill('#email', 'e2e-test@example.com');
    await page.fill('#password', 'test-password-123');
    await page.click('button[type="submit"]');

    await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/);
    await expect(page.locator('#roster-content')).toBeVisible();
    await expect(page.locator('#roster-staff-panel-fragment')).toBeVisible();
}

test.describe('Roster assignment sidebar refresh', () => {
    test('updates the staff panel immediately after assigning a linked staff member', async ({ page }) => {
        await loginAndOpenRoster(page);

        const managerEntry = page
            .locator('#roster-staff-panel-fragment .roster-staff-panel-entry[data-roster-staff-role="Manager"]')
            .first();

        await expect(managerEntry).toContainText('0');

        const assignmentSelect = page.locator('select[name="staffId"]').first();
        await assignmentSelect.selectOption('a0000000-0000-0000-0000-000000000101');

        await expect(managerEntry).toContainText('1');
    });
});
