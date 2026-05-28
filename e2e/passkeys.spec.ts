import { expect, test } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import {
    clearE2EUserPasskeys,
    enableVirtualPasskeyAuthenticator,
    gotoWhenReady,
    loginAs,
    loginAsPrivilegedUserWithFreshPasskey,
    openProfileSecuritySection,
    registerFirstPasskeyForCurrentUser,
    removeVirtualPasskeyAuthenticator,
    resetE2EUserPasskeySignCount,
    verifyCurrentUserPasskeyStepUp,
    webauthnBaseURL,
} from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

const adminEmail = 'e2e-admin@example.com';
const password = 'test-password-123';

async function passwordLogin(page: import('@playwright/test').Page, email = adminEmail) {
    await gotoWhenReady(page, '/NewSession', '#email');
    await page.fill('#email', email);
    await page.fill('#password', password);
    await page.click('button[type="submit"]');
}

async function logout(page: import('@playwright/test').Page) {
    await page.click('a:has-text("logout"), button:has-text("logout")');
    await expect(page).toHaveURL(/NewSession/, { timeout: E2E_TIMEOUT.navigation });
}

test.describe('Mandatory venue-admin passkeys', () => {
    test.setTimeout(E2E_TIMEOUT.slowTest);

    test('password login forces venue admins without passkeys to security setup', async ({ page }) => {
        clearE2EUserPasskeys(adminEmail);

        await passwordLogin(page);

        await expect(page).toHaveURL(/EditProfile.*section=security/, { timeout: E2E_TIMEOUT.navigation });
        await openProfileSecuritySection(page);
        await expect(page.getByRole('button', { name: 'Add passkey' })).toBeVisible();
        await expect(page.locator('body')).toContainText('No passkeys registered yet.');
    });

    test('venue admin can register the first passkey and access admin pages', async ({ page }) => {
        await loginAsPrivilegedUserWithFreshPasskey(page);

        await gotoWhenReady(page, '/Admin', '#admin-config-sections');

        await expect(page.locator('#admin-config-sections')).toBeVisible();
        await expect(page.getByRole('button', { name: 'Roster Groups' }).first()).toBeVisible();
        await expect(page.getByRole('button', { name: 'Roster Groups' }).first()).toHaveAttribute('aria-expanded', 'false');
    });

    test('password login with an existing passkey requires step-up before admin pages', async ({ page }) => {
        await loginAsPrivilegedUserWithFreshPasskey(page);
        await logout(page);

        await loginAs(page, adminEmail, password);
        await page.goto('/Admin');

        await verifyCurrentUserPasskeyStepUp(page);
        if (!new URL(page.url()).pathname.includes('/Admin')) {
            await gotoWhenReady(page, '/Admin', '#admin-config-sections');
        }
        await expect(page.locator('#admin-config-sections')).toBeVisible();
    });

    test('passkey login marks venue-admin access as freshly verified', async ({ page }) => {
        await loginAsPrivilegedUserWithFreshPasskey(page);
        resetE2EUserPasskeySignCount(adminEmail);
        await logout(page);

        await gotoWhenReady(page, '/NewSession', '#email');
        await page.getByRole('button', { name: 'Sign in with a passkey' }).click();
        await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });

        await gotoWhenReady(page, '/Admin', '#admin-config-sections');
        await expect(page.locator('#admin-config-sections')).toBeVisible();
    });

    test('venue admin cannot delete their last passkey', async ({ page }) => {
        await loginAsPrivilegedUserWithFreshPasskey(page);
        await openProfileSecuritySection(page);
        await expect(page.locator('#profile-security-collapse table')).toBeVisible();

        await page.getByRole('button', { name: 'Delete' }).first().click();

        await expect(page).toHaveURL(/EditProfile.*section=security/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#profile-security-collapse table tbody tr')).toHaveCount(1);
        await expect(page.locator('body')).toContainText('must keep at least one passkey');
    });

    test('adding another admin passkey uses the emailed setup-link path after password login', async ({ page }) => {
        clearE2EUserPasskeys(adminEmail);
        const firstAuthenticator = await enableVirtualPasskeyAuthenticator(page);

        await passwordLogin(page);
        await expect(page).toHaveURL(/EditProfile.*section=security/, { timeout: E2E_TIMEOUT.navigation });
        await registerFirstPasskeyForCurrentUser(page);
        await logout(page);

        await loginAs(page, adminEmail, password);
        await openProfileSecuritySection(page);
        await expect(page.getByRole('button', { name: 'Add passkey' })).toHaveCount(0);
        await page.getByRole('button', { name: 'Email setup link for another device' }).click();

        await verifyCurrentUserPasskeyStepUp(page);
        await expect(page).toHaveURL(/EditProfile.*section=security/, { timeout: E2E_TIMEOUT.navigation });

        await openProfileSecuritySection(page);
        await page.getByRole('button', { name: 'Email setup link for another device' }).click();
        await expect(page.locator('body')).toContainText('New-device passkey setup email sent.', { timeout: E2E_TIMEOUT.navigation });
        await removeVirtualPasskeyAuthenticator(firstAuthenticator);
    });
});
