import { test, expect } from '@playwright/test';
import { openRoster } from './test-helpers';

async function loginAndOpenRoster(page) {
    await openRoster(page, { email: 'e2e-test@example.com' });
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
