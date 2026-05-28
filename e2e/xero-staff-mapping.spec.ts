import { test, expect } from '@playwright/test';
import { gotoWhenReady, loginAsPrivilegedUserWithSeededPasskeySession, webauthnBaseURL } from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

test.describe('Xero admin page', () => {
    test('shows only connection chrome before Xero is connected', async ({ page }) => {
        await loginAsPrivilegedUserWithSeededPasskeySession(page, 'e2e-super-admin@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Xero', '#admin-xero-fragment');

        await expect(page.getByText('not connected')).toBeVisible();
        await expect(page.getByText('Draft timesheet submission')).toHaveCount(0);
        await expect(page.locator('#xero-timesheets-data')).toHaveCount(0);

        await expect(page.locator('.accordion')).toHaveCount(0);
        await expect(page.locator('#xero-staff-mappings-data')).toHaveCount(0);
        await expect(page.locator('#xero-pay-items-data')).toHaveCount(0);
        await expect(page.getByRole('button', { name: 'Staff mappings' })).toHaveCount(0);
        await expect(page.getByText('Pay item requirements')).toHaveCount(0);
    });
});
