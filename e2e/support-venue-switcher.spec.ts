import { expect, test } from '@playwright/test';
import {
    dialogOverlayMountDomId,
    toastMountDomAttr,
    toastOverlayMountDomId,
} from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from './timeouts';
import {
    clearCurrentSessionPasskeyVerification,
    clearE2EUserPasskeys,
    enableVirtualPasskeyAuthenticator,
    loginAsPrivilegedUserWithSeededPasskeySession,
    registerFirstSupportPasskeyForCurrentUser,
    webauthnBaseURL,
} from './support/passkeys';
import { defaultE2ERosterGroupId, openRoster } from './support/roster';
import { gotoWhenReady } from './support/runtime';
import { loginAsWithFreshBrowserSession } from './support/session';

test.use({ baseURL: webauthnBaseURL });

async function loginAsSuperAdmin(page: import('@playwright/test').Page) {
    await loginAsPrivilegedUserWithSeededPasskeySession(page, 'e2e-super-admin@example.com', 'test-password-123');
}

async function loginAsManager(page: import('@playwright/test').Page) {
    await gotoWhenReady(page, '/NewSession', '#email');
    await page.fill('#email', 'e2e-test@example.com');
    await page.fill('#password', 'test-password-123');
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWindow)/, { timeout: E2E_TIMEOUT.navigation });
    await expect(page.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
}

test.describe('Super-admin venue and user switchers', () => {
    test('impersonates and immediately exits from the desktop header without exposing emails', async ({ page }) => {
        await loginAsSuperAdmin(page);
        await openRoster(page, {
            email: 'e2e-super-admin@example.com',
            password: 'test-password-123',
            ensureEditable: false,
            useCurrentSession: true,
        });

        const userSwitcher = page.locator('#support-impersonation-user');
        await expect(userSwitcher).toBeVisible();
        await expect(userSwitcher).toContainText('Super admin');
        await expect(userSwitcher).toContainText('Alpha — Worker');
        await expect(userSwitcher).not.toContainText('@');
        const rosterUrl = page.url();

        await userSwitcher.selectOption({ label: 'Alpha — Worker' });
        await expect(page).toHaveURL(rosterUrl, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#roster-week-shell')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#support-impersonation-user option:checked')).toHaveText('Alpha — Worker');
        await expect(page.getByRole('link', { name: 'support', exact: true })).toBeVisible();
        await expect(page.getByRole('link', { name: 'admin', exact: true })).toHaveCount(0);

        await page.locator('#support-impersonation-user').selectOption({ label: 'Super admin' });
        await expect(page).toHaveURL(rosterUrl, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#roster-week-shell')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#support-impersonation-user option:checked')).toHaveText('Super admin');
        await expect(page.getByRole('link', { name: 'support', exact: true })).toBeVisible();

        await gotoWhenReady(page, '/Support', '#support-impersonation-user');
        await page.locator('#support-impersonation-user').selectOption({ label: 'Alpha — Worker' });
        await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWindow)/, { timeout: E2E_TIMEOUT.navigation });
        const fallbackToast = page.locator(`#${toastOverlayMountDomId} [${toastMountDomAttr}]`);
        await expect(fallbackToast).toContainText('That page is not available for the resulting account. Showing its Roster instead.');
    });

    test('passkey overlay keeps context and requires the blocked switch to be repeated', async ({ page }) => {
        clearE2EUserPasskeys('e2e-super-admin@example.com');
        await enableVirtualPasskeyAuthenticator(page);
        await loginAsWithFreshBrowserSession(page, 'e2e-super-admin@example.com', 'test-password-123');
        await registerFirstSupportPasskeyForCurrentUser(page);
        await gotoWhenReady(page, '/RosterWeeks', '#roster-content');
        await openRoster(page, {
            email: 'e2e-super-admin@example.com',
            password: 'test-password-123',
            ensureEditable: false,
            useCurrentSession: true,
        });
        await clearCurrentSessionPasskeyVerification(page);
        const rosterUrl = page.url();
        const userSwitcher = page.locator('#support-impersonation-user');
        const finishStepUpResponse = page.waitForResponse(
            (response) => new URL(response.url()).pathname === '/FinishPasskeyStepUpAuthentication',
            { timeout: E2E_TIMEOUT.passkey },
        );

        await userSwitcher.selectOption({ label: 'Alpha — Worker' });
        expect((await finishStepUpResponse).status()).toBe(200);
        await expect(page.locator(`#${dialogOverlayMountDomId}`)).toBeEmpty({ timeout: E2E_TIMEOUT.passkey });
        await expect(page).toHaveURL(rosterUrl);
        await expect(userSwitcher).toHaveValue('');

        await userSwitcher.selectOption({ label: 'Alpha — Worker' });
        await expect(page).toHaveURL(rosterUrl, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#support-impersonation-user option:checked')).toHaveText('Alpha — Worker');
    });

    test('keeps impersonation isolated between concurrent founder sessions', async ({ browser }) => {
        const firstContext = await browser.newContext({ baseURL: webauthnBaseURL });
        const secondContext = await browser.newContext({ baseURL: webauthnBaseURL });
        const firstPage = await firstContext.newPage();
        const secondPage = await secondContext.newPage();

        try {
            await loginAsSuperAdmin(firstPage);
            await loginAsSuperAdmin(secondPage);
            await openRoster(firstPage, {
                email: 'e2e-super-admin@example.com',
                password: 'test-password-123',
                ensureEditable: false,
                useCurrentSession: true,
            });
            await openRoster(secondPage, {
                email: 'e2e-super-admin@example.com',
                password: 'test-password-123',
                ensureEditable: false,
                useCurrentSession: true,
            });

            await firstPage.locator('#support-impersonation-user').selectOption({ label: 'Alpha — Worker' });
            await secondPage.locator('#support-impersonation-user').selectOption({ label: 'Alpha — Worker' });
            await expect(firstPage.locator('#support-impersonation-user option:checked')).toHaveText('Alpha — Worker');
            await expect(secondPage.locator('#support-impersonation-user option:checked')).toHaveText('Alpha — Worker');

            await firstPage.locator('#support-impersonation-user').selectOption({ label: 'Super admin' });
            await expect(firstPage.locator('#support-impersonation-user option:checked')).toHaveText('Super admin');
            await secondPage.reload();
            await expect(secondPage.locator('#support-impersonation-user option:checked')).toHaveText('Alpha — Worker');
        } finally {
            await firstContext.close();
            await secondContext.close();
        }
    });

    test('shows a venue switcher in the header and switches active venue', async ({ page }) => {
        await loginAsSuperAdmin(page);

        await gotoWhenReady(page, '/LeaveRequests', '#leave-requests-content');
        await expect(page.locator('#support-venue-switch')).toBeVisible();
        await expect(page.locator('label[for="support-venue-switch"]')).toHaveText('Support venue');
        await expect(page.locator('label[for="support-venue-switch"]')).toBeVisible();
        await expect(page.locator('#support-venue-switch')).toContainText('e2e-alpha-venue');
        await expect(page.locator('#support-venue-switch')).toContainText('e2e-beta-venue');

        await page.selectOption('#support-venue-switch', { label: 'e2e-beta-venue' });
        await expect(page).toHaveURL(/LeaveRequests/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#leave-requests-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('body')).not.toContainText(/FORBIDDEN/i);

        await gotoWhenReady(page, '/Support', '#support-venue-switch');
        await expect(page.locator('#support-venue-switch')).toContainText('e2e-beta-venue');
    });

    test('switching from a venue-specific roster URL opens the new venue roster', async ({ page }) => {
        await loginAsSuperAdmin(page);
        await openRoster(page, {
            email: 'e2e-super-admin@example.com',
            password: 'test-password-123',
            ensureEditable: false,
            useCurrentSession: true,
        });

        await page.selectOption('#support-impersonation-user', { label: 'Alpha — Worker' });
        await expect(page.locator('#support-impersonation-user option:checked')).toHaveText('Alpha — Worker');

        await page.selectOption('#support-venue-switch', { label: 'e2e-beta-venue' });

        await expect(page).toHaveURL(
            (url) =>
                url.pathname === '/ShowRosterWindow'
                && url.searchParams.has('anchorDate')
                && url.searchParams.has('rosterGroupId')
                && url.searchParams.get('rosterGroupId') !== defaultE2ERosterGroupId,
            { timeout: E2E_TIMEOUT.navigation },
        );
        await expect(page.locator('#roster-week-shell')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#support-venue-switch option:checked')).toHaveText('e2e-beta-venue');
        await expect(page.locator('#support-impersonation-user option:checked')).toHaveText('Super admin');
        await expect(page.locator('body')).not.toContainText(/FORBIDDEN/i);
    });

    test('does not show the venue switcher for ordinary venue admins', async ({ page }) => {
        await loginAsManager(page);

        await expect(page.locator('#support-venue-switch')).toHaveCount(0);
        await expect(page.locator('#support-impersonation-user')).toHaveCount(0);
    });
});
