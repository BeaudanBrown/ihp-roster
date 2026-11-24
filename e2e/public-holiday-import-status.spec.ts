import { expect, test } from '@playwright/test';
import { loginAsPrivilegedUserWithSeededPasskeySession, webauthnBaseURL } from './support/passkeys';
import { gotoWhenReady } from './support/runtime';

test.use({ baseURL: webauthnBaseURL });

test('Support mounts read-only DataVic import status and calendar coverage', async ({ page }) => {
    await loginAsPrivilegedUserWithSeededPasskeySession(page, 'e2e-super-admin@example.com', 'test-password-123');
    await gotoWhenReady(page, '/Support', '#support-public-holidays');

    const section = page.locator('#support-public-holidays');
    const surface = page.locator('[data-bepis-surface="support"][data-bepis-surface-config]');
    await expect(surface).toHaveAttribute('data-bepis-surface-config', /ShowPublicHolidaysSection/);
    await expect(section).toContainText('No automated DataVic import job recorded yet.');
    await expect(section).toContainText('No accepted DataVic import recorded yet.');
    await expect(section.getByRole('columnheader', { name: 'Cached holidays' })).toBeVisible();
    await expect(section.getByRole('table').getByRole('row')).toHaveCount(4);
    await expect(section.locator('form, button')).toHaveCount(0);
});
