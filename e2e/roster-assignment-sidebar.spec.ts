import { test, expect, type Page } from '@playwright/test';
import { rosterStaffPanelSortRowDomAttr } from '../frontend/ts/generated/contracts';
import { assignRosterShiftStaff, existingRosterShiftLaunchers, openRoster } from './support/roster';

async function loginAndOpenRoster(page: Page) {
    await openRoster(page, { email: 'e2e-test@example.com' });
    await expect(page.locator('#roster-staff-panel-fragment')).toBeVisible();
}

test.describe('Roster assignment sidebar refresh', () => {
    test('updates the staff panel immediately after assigning a linked staff member', async ({ page }) => {
        await loginAndOpenRoster(page);

        const managerEntry = page
            .locator(`#roster-staff-panel-fragment [${rosterStaffPanelSortRowDomAttr}]`)
            .filter({ hasText: 'Manager' })
            .first();

        await expect(managerEntry).toContainText('0');

        const assignmentLauncher = existingRosterShiftLaunchers(page).first();
        await assignRosterShiftStaff(page, assignmentLauncher, 'a0000000-0000-0000-0000-000000000101');

        await expect(managerEntry).toContainText('1');
    });
});
