import { expect, test } from '@playwright/test';
import { E2E_TIMEOUT, loginAs } from './test-helpers';

test.describe('Browser failure recovery', () => {
    test('shows a useful recovery page for a malformed roster bookmark', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');

        const response = await page.goto(
            '/ShowRosterWindow?anchorDate=2026-09-02&rosterGroupId=e3179940-4716-405e-b433-70aaa33a4f7',
        );

        expect(response?.status()).toBe(400);
        await expect(page.getByRole('heading', { name: 'This link or request is invalid' })).toBeVisible();
        await expect(page.locator('body')).not.toContainText('Action not found');

        await page.getByRole('link', { name: 'Return to Bepis' }).click();
        await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWindow)/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
    });
});
