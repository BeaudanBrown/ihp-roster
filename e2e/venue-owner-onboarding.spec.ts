import { test, expect, Page } from '@playwright/test';
import {
    clearMailhogInbox,
    clearE2EUserPasskeys,
    enableVirtualPasskeyAuthenticator,
    extractFirstUrl,
    gotoWhenReady,
    inviteUrlForCurrentBase,
    mailhogMessageSubject,
    mailhogMessageText,
    registerFirstSupportPasskeyForCurrentUser,
    waitForMailhogMessage,
    webauthnBaseURL,
} from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

async function loginAsSuperAdmin(page: Page) {
    clearE2EUserPasskeys('e2e-super-admin@example.com');
    await enableVirtualPasskeyAuthenticator(page);
    await gotoWhenReady(page, '/NewSession', '#email');
    await page.fill('#email', 'e2e-super-admin@example.com');
    await page.fill('#password', 'test-password-123');
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL(/Support/, { timeout: 60000 });
    await expect(page.locator('#support-create-onboarding-email')).toBeVisible({ timeout: 60000 });
    await registerFirstSupportPasskeyForCurrentUser(page);
}

async function openSupport(page: Page) {
    await gotoWhenReady(page, '/Support', '#support-create-onboarding-email');
}

function onboardingInviteRow(page: Page, email: string) {
    return page.locator('table tbody tr').filter({ hasText: email }).first();
}

test.describe('Venue owner onboarding invites', () => {
    test.setTimeout(120000);

    test.beforeEach(async ({ request }) => {
        await clearMailhogInbox(request);
    });

    test('super-admin can send a venue owner invite email and support shows it as sent', async ({ page, request }) => {
        const ownerEmail = `e2e-owner-mail-${Date.now()}@example.com`;

        await loginAsSuperAdmin(page);
        await openSupport(page);

        await page.fill('#support-create-onboarding-email', ownerEmail);
        await page.getByRole('button', { name: 'Send Owner Invite' }).click();

        const row = onboardingInviteRow(page, ownerEmail);
        await expect(row).toBeVisible();
        await expect(row).toContainText(/Queued|Sent/);

        const message = await waitForMailhogMessage(request, ownerEmail, 30000);
        expect(mailhogMessageSubject(message)).toContain('Create your Bepis venue');

        await openSupport(page);
        await expect(onboardingInviteRow(page, ownerEmail)).toContainText('Sent');
        await expect(onboardingInviteRow(page, ownerEmail)).toContainText('Pending');
    });

    test('owner can redeem an emailed onboarding invite, create a Tuesday-start venue, and the link cannot be reused', async ({ browser, page, request, baseURL }) => {
        const suffix = Date.now();
        const ownerEmail = `e2e-owner-onboarding-${suffix}@example.com`;
        const venueName = `e2e-owner-venue-${suffix}`;

        await loginAsSuperAdmin(page);
        await openSupport(page);

        await page.fill('#support-create-onboarding-email', ownerEmail);
        await page.getByRole('button', { name: 'Send Owner Invite' }).click();

        const supportRow = onboardingInviteRow(page, ownerEmail);
        await expect(supportRow).toBeVisible();

        const message = await waitForMailhogMessage(request, ownerEmail, 30000);
        expect(mailhogMessageSubject(message)).toContain('Create your Bepis venue');
        const inviteUrl = inviteUrlForCurrentBase(extractFirstUrl(mailhogMessageText(message)), baseURL!);

        const ownerContext = await browser.newContext();
        const ownerPage = await ownerContext.newPage();

        await gotoWhenReady(ownerPage, inviteUrl, '#email');
        await expect(ownerPage.locator('#email')).toHaveValue(ownerEmail);
        await expect(ownerPage.locator('#email')).toHaveAttribute('readonly', 'readonly');
        await ownerPage.fill('#passwordHash', 'test-password-123');
        await ownerPage.fill('#passwordConfirmation', 'test-password-123');
        await ownerPage.fill('#venue-name', venueName);
        await ownerPage.fill('#venue-timezone', 'Pacific/Auckland');
        await ownerPage.selectOption('#venue-roster-week-starts-on', '2');
        await ownerPage.getByRole('button', { name: 'Create Account And Venue' }).click();

        await expect(ownerPage).toHaveURL(/EditProfile/, { timeout: 60000 });
        await expect(ownerPage.locator('#profile-content-fragment')).toContainText(
            'Shift preferences will appear once this staff member is assigned to at least one roster group.',
        );

        await gotoWhenReady(ownerPage, inviteUrl, 'body');
        await expect(ownerPage.locator('body')).toContainText('Invitation Required');

        await openSupport(page);
        await expect(onboardingInviteRow(page, ownerEmail)).toContainText('Accepted');
        await expect(onboardingInviteRow(page, ownerEmail)).toContainText('Sent');

        await ownerContext.close();
    });
});
