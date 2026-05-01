import { test, expect, Page } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import {
    clearMailhogInbox,
    expectMailhogMessageCount,
    extractFirstUrl,
    gotoWhenReady,
    inviteUrlForCurrentBase,
    mailhogMessageSubject,
    mailhogMessageText,
    openAdminWithFreshPasskey,
    waitForMailhogMessage,
    webauthnBaseURL,
} from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

async function openInvitesSection(page: Page) {
    const toggle = page.locator('#invites-heading button');
    if ((await toggle.getAttribute('aria-expanded')) !== 'true') {
        await toggle.click();
    }
    await expect(page.locator('#admin-invites-fragment')).toBeVisible();
}

function inviteRow(page: Page, email: string) {
    return page.locator('#admin-invites-fragment tbody tr').filter({ hasText: email }).first();
}

async function submitInviteCreateForm(page: Page) {
    await page.locator('#admin-invites-fragment form').getByRole('button', { name: 'Send' }).click();
}

test.describe('Admin invites', () => {
    test.setTimeout(E2E_TIMEOUT.slowTest);

    test.beforeEach(async ({ request }) => {
        await clearMailhogInbox(request);
    });

    test('admin can queue and revoke an invite, and revoked links stop working', async ({ page, request, baseURL }) => {
        const inviteeEmail = `e2e-revoke-${Date.now()}@example.com`;

        await openAdminWithFreshPasskey(page);
        await openInvitesSection(page);

        await page.fill('#new-invite-email', inviteeEmail);
        await submitInviteCreateForm(page);

        const row = inviteRow(page, inviteeEmail);
        await expect(row).toBeVisible();
        await expect(row).toContainText(/Queued|Sent/);
        await expect(row.getByRole('button', { name: 'Revoke' })).toBeVisible();

        const message = await waitForMailhogMessage(request, inviteeEmail, E2E_TIMEOUT.mailhog);
        expect(mailhogMessageSubject(message)).toContain("You're invited");
        const inviteUrl = inviteUrlForCurrentBase(extractFirstUrl(mailhogMessageText(message)), baseURL!);

        await openInvitesSection(page);
        const revokableRow = inviteRow(page, inviteeEmail);
        await expect(revokableRow.getByRole('button', { name: 'Revoke' })).toBeVisible();
        await revokableRow.getByRole('button', { name: 'Revoke' }).click();
        await expect(revokableRow).toContainText('Revoked');
        await expect(revokableRow.getByRole('button', { name: 'Revoke' })).toHaveCount(0);

        await gotoWhenReady(page, inviteUrl, 'body');
        await expect(page.locator('body')).toContainText('Invitation Required');
    });

    test('accepted invites verify the email, avoid a second email, and show accepted status when the admin revisits invites', async ({ browser, page, request, baseURL }) => {
        const inviteeEmail = `e2e-accept-${Date.now()}@example.com`;

        await openAdminWithFreshPasskey(page);
        await openInvitesSection(page);

        await page.fill('#new-invite-email', inviteeEmail);
        await submitInviteCreateForm(page);

        const row = inviteRow(page, inviteeEmail);
        await expect(row).toBeVisible();
        await expect(row).toContainText(/Queued|Sent/);

        const message = await waitForMailhogMessage(request, inviteeEmail, E2E_TIMEOUT.mailhog);
        const inviteUrl = inviteUrlForCurrentBase(extractFirstUrl(mailhogMessageText(message)), baseURL!);

        const inviteeContext = await browser.newContext();
        const inviteePage = await inviteeContext.newPage();

        await gotoWhenReady(inviteePage, inviteUrl, '#email');
        await expect(inviteePage.locator('#email')).toHaveValue(inviteeEmail);
        await expect(inviteePage.locator('#email')).toHaveAttribute('readonly', 'readonly');
        await inviteePage.fill('input[name="passwordHash"]', 'test-password-123');
        await inviteePage.fill('input[name="passwordConfirmation"]', 'test-password-123');
        await inviteePage.locator('form').evaluate((form) => (form as HTMLFormElement).requestSubmit());
        await expect(inviteePage).toHaveURL(/EditProfile/, { timeout: E2E_TIMEOUT.navigation });

        await gotoWhenReady(page, '/Admin', '#admin-config-sections');
        await openInvitesSection(page);
        await expect(inviteRow(page, inviteeEmail)).toContainText('Accepted');
        await expectMailhogMessageCount(request, inviteeEmail, 1, 10000);

        await inviteeContext.close();
    });
});
