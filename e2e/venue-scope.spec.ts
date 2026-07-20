import { test, expect, type Page } from '@playwright/test';
import { rosterStaffPanelSortRowDomAttr } from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady } from './test-helpers';

async function login(page: Page) {
    await gotoWhenReady(page, '/NewSession', '#email');
    await page.fill('#email', 'e2e-test@example.com');
    await page.fill('#password', 'test-password-123');
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/, { timeout: E2E_TIMEOUT.navigation });
    await expect(page.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
}

test.describe('Venue-scoped navigation', () => {
    test('login resolves the current venue and scopes roster, timesheets, and leave views', async ({ page }) => {
        await login(page);

        const staffRows = page.locator(`#roster-staff-panel-fragment [${rosterStaffPanelSortRowDomAttr}]`);
        await expect(staffRows.filter({ hasText: 'Alpha' })).toHaveCount(1);
        await expect(staffRows.filter({ hasText: 'Beta' })).toHaveCount(0);

        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');
        await expect(page.locator('#timesheet-week-shell')).toContainText('Alpha Crew');
        await expect(page.locator('#timesheet-week-shell')).not.toContainText('Beta Crew');

        await gotoWhenReady(page, '/LeaveRequests', '#leave-requests-content');
        await expect(page.locator('#leave-requests-content')).toContainText('Alpha Crew');
        await expect(page.locator('#leave-requests-content')).not.toContainText('Beta Crew');
    });
});
