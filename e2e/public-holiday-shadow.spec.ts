import { expect, test } from '@playwright/test';
import { loginAsPrivilegedUserWithSeededPasskeySession, webauthnBaseURL } from './support/passkeys';
import { gotoWhenReady } from './support/runtime';
import { E2E_TIMEOUT } from './timeouts';

// Run with DATAVIC_KEY empty: browser acceptance must never call the government.
test.use({ baseURL: webauthnBaseURL });

test('Support shadow fetch keeps the cached authority and publishes safe failure evidence', async ({ page }) => {
    test.skip(Boolean(process.env.DATAVIC_KEY), 'Requires isolated worker with DATAVIC_KEY empty; never use live provider credentials.');
    await loginAsPrivilegedUserWithSeededPasskeySession(page, 'e2e-super-admin@example.com', 'test-password-123');
    await gotoWhenReady(page, '/Support', '#support-public-holidays');
    const section = page.locator('#support-public-holidays');
    await expect(section).toContainText('Anonymous refresh is disabled');
    await expect(section.getByRole('button', { name: 'Refresh public holidays', exact: true })).toHaveCount(0);
    const cachedBefore = await section.getByRole('table').innerText();
    await section.getByRole('button', { name: 'Run shadow fetch', exact: true }).click();
    await expect(section).toContainText('Shadow fetch failed; no dates imported.', { timeout: E2E_TIMEOUT.navigation });
    await expect(section).toContainText('Requested years:');
    await expect(section.getByRole('table')).toHaveText(cachedBefore, { useInnerText: true });
    await expect(section).toContainText('shadow success does not renew source freshness');
});
