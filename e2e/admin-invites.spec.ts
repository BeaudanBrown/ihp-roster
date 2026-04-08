import { test, expect, Page } from '@playwright/test';
import {
    clearMailhogInbox,
    expectMailhogMessageCount,
    extractFirstUrl,
    gotoWhenReady,
    loginAs,
    mailhogMessageSubject,
    mailhogMessageText,
    waitForMailhogMessage,
} from './test-helpers';

function inviteUrlForCurrentBase(rawUrl: string, baseURL: string) {
    const parsed = new URL(rawUrl);
    return new URL(`${parsed.pathname}${parsed.search}`, baseURL).toString();
}

async function openInvitesSection(page: Page) {
    await page.locator('#invites-heading button').click();
    await expect(page.locator('#admin-invites-fragment')).toBeVisible();
}

test.describe('Admin invites', () => {
    test.setTimeout(120000);

    test.beforeEach(async ({ request }) => {
        await clearMailhogInbox(request);
    });

    test('admin can queue and revoke an invite, and revoked links stop working', async ({ page, request, baseURL }) => {
        const inviteeEmail = `e2e-revoke-${Date.now()}@example.com`;

        await loginAs(page, 'e2e-admin@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Admin', '#admin-config-sections');
        await openInvitesSection(page);

        await page.fill('#new-invite-email', inviteeEmail);
        await page.getByRole('button', { name: 'Queue Invite Email' }).click();

        const row = page.locator('#admin-invites-fragment tbody tr').filter({ hasText: inviteeEmail }).first();
        await expect(row).toBeVisible();
        await expect(row).toContainText(/Queued|Sent/);

        const message = await waitForMailhogMessage(request, inviteeEmail, 30000);
        expect(mailhogMessageSubject(message)).toContain("You're invited");
        const inviteUrl = inviteUrlForCurrentBase(extractFirstUrl(mailhogMessageText(message)), baseURL!);

        await row.getByRole('button', { name: 'Revoke' }).click();
        await expect(row).toContainText('Revoked');
        await expect(row.getByRole('button', { name: 'Revoke' })).toHaveCount(0);

        await gotoWhenReady(page, inviteUrl, 'body');
        await expect(page.locator('body')).toContainText('Invitation Required');
    });

    test('accepted invites verify the email, avoid a second email, and show accepted status when the admin revisits invites', async ({ browser, page, request, baseURL }) => {
        const inviteeEmail = `e2e-accept-${Date.now()}@example.com`;

        await loginAs(page, 'e2e-admin@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Admin', '#admin-config-sections');
        await openInvitesSection(page);

        await page.fill('#new-invite-email', inviteeEmail);
        await page.getByRole('button', { name: 'Queue Invite Email' }).click();

        const row = page.locator('#admin-invites-fragment tbody tr').filter({ hasText: inviteeEmail }).first();
        await expect(row).toBeVisible();
        await expect(row).toContainText(/Queued|Sent/);

        const message = await waitForMailhogMessage(request, inviteeEmail, 30000);
        const inviteUrl = inviteUrlForCurrentBase(extractFirstUrl(mailhogMessageText(message)), baseURL!);

        const inviteeContext = await browser.newContext();
        const inviteePage = await inviteeContext.newPage();

        await gotoWhenReady(inviteePage, inviteUrl, '#email');
        await expect(inviteePage.locator('#email')).toHaveValue(inviteeEmail);
        await expect(inviteePage.locator('#email')).toHaveAttribute('readonly', 'readonly');
        await inviteePage.fill('input[name="passwordHash"]', 'test-password-123');
        await inviteePage.fill('input[name="passwordConfirmation"]', 'test-password-123');
        await inviteePage.locator('form').evaluate((form) => (form as HTMLFormElement).requestSubmit());
        await expect(inviteePage).toHaveURL(/EditProfile/, { timeout: 60000 });

        await gotoWhenReady(page, '/Admin', '#admin-config-sections');
        await openInvitesSection(page);
        await expect(page.locator('#admin-invites-fragment tbody tr').filter({ hasText: inviteeEmail }).first()).toContainText('Accepted');
        await expectMailhogMessageCount(request, inviteeEmail, 1, 10000);

        await inviteeContext.close();
    });
});
