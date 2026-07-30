import { test, expect, Page } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import {
    extractFirstUrl,
    gotoWhenReady,
    inviteUrlForCurrentBase,
    mailhogMessageSubject,
    mailhogMessageText,
    loginAsPrivilegedUserWithSeededPasskeySession,
    uniqueE2EValue,
    waitForMailhogMessage,
    webauthnBaseURL,
} from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

async function loginAsSuperAdmin(page: Page) {
    await loginAsPrivilegedUserWithSeededPasskeySession(page, 'e2e-super-admin@example.com', 'test-password-123');
    await gotoWhenReady(page, '/Support', '#support-create-onboarding-email');
}

async function openSupport(page: Page) {
    await gotoWhenReady(page, '/Support', '#support-create-onboarding-email');
}

function onboardingInviteRow(page: Page, email: string) {
    return page.locator('table tbody tr').filter({ hasText: email }).first();
}

test.describe('Venue owner onboarding invites', () => {
    test.setTimeout(E2E_TIMEOUT.slowTest);

    test('super-admin can send a venue owner invite email and support shows it as sent', async ({ page, request }) => {
        const ownerEmail = `${uniqueE2EValue('e2e-owner-mail')}@example.com`;

        await loginAsSuperAdmin(page);
        await openSupport(page);

        await page.fill('#support-create-onboarding-email', ownerEmail);
        await page.getByRole('button', { name: 'Send Owner Invite' }).click();

        const row = onboardingInviteRow(page, ownerEmail);
        await expect(row).toBeVisible();
        await expect(row).toContainText(/Queued|Sent/);

        const message = await waitForMailhogMessage(request, ownerEmail, E2E_TIMEOUT.mailhog);
        expect(mailhogMessageSubject(message)).toContain('Create your Bepis venue');

        await openSupport(page);
        await expect(onboardingInviteRow(page, ownerEmail)).toContainText('Sent');
        await expect(onboardingInviteRow(page, ownerEmail)).toContainText('Pending');
    });

    test('support renews an owner invite with a corrected email and invalidates the old link', async ({ browser, page, request, baseURL }) => {
        const suffix = uniqueE2EValue('e2e-owner-renewal');
        const originalEmail = `${suffix}-old@example.com`;
        const correctedEmail = `${suffix}-corrected@example.com`;

        await loginAsSuperAdmin(page);
        await page.fill('#support-create-onboarding-email', originalEmail);
        await page.getByRole('button', { name: 'Send Owner Invite' }).click();

        const originalMessage = await waitForMailhogMessage(request, originalEmail, E2E_TIMEOUT.mailhog);
        const originalInviteUrl = inviteUrlForCurrentBase(extractFirstUrl(mailhogMessageText(originalMessage)), baseURL!);

        const originalRow = onboardingInviteRow(page, originalEmail);
        await originalRow.getByLabel('Corrected owner email').fill(correctedEmail);
        await originalRow.getByRole('button', { name: 'Renew' }).click();

        const correctedMessage = await waitForMailhogMessage(request, correctedEmail, E2E_TIMEOUT.mailhog);
        const correctedInviteUrl = inviteUrlForCurrentBase(extractFirstUrl(mailhogMessageText(correctedMessage)), baseURL!);
        expect(correctedInviteUrl).not.toBe(originalInviteUrl);

        await openSupport(page);
        await expect(onboardingInviteRow(page, originalEmail)).toContainText('Revoked');
        await expect(onboardingInviteRow(page, correctedEmail)).toContainText('Pending');

        const ownerContext = await browser.newContext();
        const ownerPage = await ownerContext.newPage();
        await gotoWhenReady(ownerPage, originalInviteUrl, 'body');
        await expect(ownerPage.locator('body')).toContainText('Invitation Required');
        await gotoWhenReady(ownerPage, correctedInviteUrl, '#email');
        await expect(ownerPage.locator('#email')).toHaveValue(correctedEmail);
        await ownerContext.close();
    });

    test('owner can redeem an emailed onboarding invite, create a Tuesday-start venue, and the link cannot be reused', async ({ browser, page, request, baseURL }) => {
        const suffix = uniqueE2EValue('e2e-owner-onboarding');
        const ownerEmail = `${suffix}@example.com`;
        const venueName = `e2e-owner-venue-${suffix}`;

        await loginAsSuperAdmin(page);
        await openSupport(page);

        await page.fill('#support-create-onboarding-email', ownerEmail);
        await page.getByRole('button', { name: 'Send Owner Invite' }).click();

        const supportRow = onboardingInviteRow(page, ownerEmail);
        await expect(supportRow).toBeVisible();

        const message = await waitForMailhogMessage(request, ownerEmail, E2E_TIMEOUT.mailhog);
        expect(mailhogMessageSubject(message)).toContain('Create your Bepis venue');
        const inviteUrl = inviteUrlForCurrentBase(extractFirstUrl(mailhogMessageText(message)), baseURL!);

        const ownerContext = await browser.newContext();
        const ownerPage = await ownerContext.newPage();

        await gotoWhenReady(ownerPage, inviteUrl, '#email');
        await expect(ownerPage.locator('body')).toContainText('Account Details');
        await expect(ownerPage.locator('body')).toContainText('Show shift end times in roster');
        await expect(ownerPage.locator('body')).not.toContainText('Auto-create pending timesheets');
        await expect(ownerPage.locator('#email')).toHaveValue(ownerEmail);
        await expect(ownerPage.locator('#email')).toBeDisabled();
        await ownerPage.fill('#passwordHash', 'test-password-123');
        await ownerPage.fill('#passwordConfirmation', 'test-password-123');
        await ownerPage.fill('#venue-name', venueName);
        await expect(ownerPage.locator('#venue-timezone')).toHaveCount(0);
        await ownerPage.selectOption('#venue-roster-week-starts-on', '2');
        await ownerPage.fill('#firstName', 'E2E');
        await ownerPage.fill('#lastName', 'Owner');
        await ownerPage.fill('#phone', '0400000000');
        await ownerPage.selectOption('#idealShiftsPerWeek', '3');
        await ownerPage.fill('#emergencyContactName', 'Emergency Contact');
        await ownerPage.fill('#emergencyContactPhone', '0411111111');
        await ownerPage.getByRole('button', { name: 'Create Account And Venue' }).click();

        await expect(ownerPage).toHaveURL(/(RosterWeeks|ShowRosterWeek)/, { timeout: E2E_TIMEOUT.navigation });
        await expect(ownerPage.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });

        await gotoWhenReady(ownerPage, inviteUrl, 'body');
        await expect(ownerPage.locator('body')).toContainText('Invitation Required');

        await openSupport(page);
        await expect(onboardingInviteRow(page, ownerEmail)).toContainText('Accepted');
        await expect(onboardingInviteRow(page, ownerEmail)).toContainText('Sent');

        await ownerContext.close();
    });
});
