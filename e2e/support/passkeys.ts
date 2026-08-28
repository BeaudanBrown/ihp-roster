import { expect, type Page } from '@playwright/test';
import { passkeyActionButtonDomAttr, passkeyRegistrationDomAttr } from '../../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from '../timeouts';
import { runSql, sqlString } from './database';
import { gotoWhenReady } from './runtime';
import { loginAs } from './session';

export const webauthnBaseURL = (process.env.E2E_BASE_URL ?? 'http://127.0.0.1:8000').replace('127.0.0.1', 'localhost');

export function clearE2EUserPasskeys(email: string) {
    runSql(`DELETE FROM passkeys WHERE user_id = (SELECT id FROM users WHERE email = ${sqlString(email)});`);
}

export function resetE2EUserPasskeySignCount(email: string) {
    runSql(`UPDATE passkeys SET sign_count = 0 WHERE user_id = (SELECT id FROM users WHERE email = ${sqlString(email)});`);
}

export async function enableVirtualPasskeyAuthenticator(page: Page) {
    const cdp = await page.context().newCDPSession(page);
    await cdp.send('WebAuthn.enable');
    const { authenticatorId } = await cdp.send('WebAuthn.addVirtualAuthenticator', {
        options: {
            protocol: 'ctap2',
            transport: 'internal',
            hasResidentKey: true,
            hasUserVerification: true,
            isUserVerified: true,
            automaticPresenceSimulation: true,
        },
    });
    await cdp.send('WebAuthn.setAutomaticPresenceSimulation', {
        authenticatorId,
        enabled: true,
    });
    return { cdp, authenticatorId };
}

export async function removeVirtualPasskeyAuthenticator(authenticator: Awaited<ReturnType<typeof enableVirtualPasskeyAuthenticator>>) {
    await authenticator.cdp.send('WebAuthn.removeVirtualAuthenticator', {
        authenticatorId: authenticator.authenticatorId,
    });
}

export async function registerFirstPasskeyForCurrentUser(page: Page) {
    await openProfileSecuritySection(page);
    if (!(await passkeyRegistrationButton(page).isVisible().catch(() => false))) {
        await page.getByRole('link', { name: 'Create passkey' }).click();
        await expect(page.locator(`[${passkeyRegistrationDomAttr}]`)).toBeVisible({ timeout: E2E_TIMEOUT.action });
    }
    await registerFirstPasskeyFromVisibleControl(page);
    await openProfileSecuritySection(page);
    await expect(currentPasskeyTable(page).locator('tbody tr')).toHaveCount(1, { timeout: E2E_TIMEOUT.passkey });
}

export async function registerFirstSupportPasskeyForCurrentUser(page: Page) {
    await gotoWhenReady(page, '/Support', '#support-impersonation-user');
    if (!(await passkeyRegistrationButton(page).isVisible().catch(() => false))) {
        await page.getByRole('link', { name: 'Create passkey' }).click();
        await expect(page.locator(`[${passkeyRegistrationDomAttr}]`)).toBeVisible({ timeout: E2E_TIMEOUT.action });
    }
    await registerFirstPasskeyFromVisibleControl(page);
    await gotoWhenReady(page, '/Support', '#support-impersonation-user');
    await expect(currentPasskeyTable(page).locator('tbody tr')).toHaveCount(1, { timeout: E2E_TIMEOUT.passkey });
}

export async function registerFirstPasskeyFromVisibleControl(page: Page) {
    const registerButton = passkeyRegistrationButton(page);
    await expect(registerButton).toBeVisible({ timeout: E2E_TIMEOUT.action });
    await Promise.all([
        page.waitForResponse(
            (response) => new URL(response.url()).pathname.includes('FinishPasskeyRegistration') && response.status() === 200,
            { timeout: E2E_TIMEOUT.passkey },
        ),
        registerButton.click(),
    ]);
}

function passkeyRegistrationButton(page: Page) {
    return page.locator(`[${passkeyRegistrationDomAttr}] [${passkeyActionButtonDomAttr}]`).first();
}

function currentPasskeyTable(page: Page) {
    return page.locator('table').filter({ has: page.getByRole('columnheader', { name: 'Last used' }) }).first();
}

export async function openProfileSecuritySection(page: Page) {
    await gotoWhenReady(page, '/EditProfile?section=security', '#profile-content-fragment');
    const securityToggle = page.getByRole('button', { name: 'Sign-In Methods' });
    if ((await securityToggle.getAttribute('aria-expanded')) !== 'true') {
        await securityToggle.click();
    }
    await expect(page.locator('#profile-security-collapse')).toBeVisible();
}

async function setCurrentSessionPasskeyVerification(page: Page, verified: boolean) {
    const token = process.env.E2E_TEST_TOKEN;
    if (!token) {
        throw new Error('E2E_TEST_TOKEN is required to update seeded passkey session verification.');
    }

    const responseStatus = await page.evaluate(
        async ({ endpoint, submittedToken, shouldBeVerified }) => {
            const response = await fetch(endpoint, {
                method: 'POST',
                headers: {
                    'X-E2E-Test-Token': submittedToken,
                    ...(shouldBeVerified ? {} : { 'X-E2E-Passkey-Verified': 'false' }),
                },
            });
            return response.status;
        },
        {
            endpoint: new URL('/__e2e/mark-passkey-verified', page.url()).toString(),
            submittedToken: token,
            shouldBeVerified: verified,
        },
    );
    expect(responseStatus).toBe(200);
}

export async function clearCurrentSessionPasskeyVerification(page: Page) {
    await setCurrentSessionPasskeyVerification(page, false);
}

export async function markCurrentSessionPasskeyVerified(page: Page) {
    await setCurrentSessionPasskeyVerification(page, true);
}

export async function loginAsPrivilegedUserWithSeededPasskeySession(
    page: Page,
    email = 'e2e-admin@example.com',
    password = 'test-password-123',
) {
    await loginAs(page, email, password);
    await page.waitForLoadState('networkidle', { timeout: E2E_TIMEOUT.action }).catch(() => {});
    await markCurrentSessionPasskeyVerified(page);
}

export async function openAdminWithSeededPasskeySession(page: Page) {
    await loginAsPrivilegedUserWithSeededPasskeySession(page);
    await gotoWhenReady(page, '/Admin', '#admin-config-sections');
}

export async function loginAsPrivilegedUserWithFreshPasskey(
    page: Page,
    email = 'e2e-admin@example.com',
    password = 'test-password-123',
) {
    clearE2EUserPasskeys(email);
    await enableVirtualPasskeyAuthenticator(page);

    await gotoWhenReady(page, '/NewSession', '#email');
    await page.fill('#email', email);
    await page.fill('#password', password);
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWindow|Support)/, { timeout: E2E_TIMEOUT.navigation });

    if (page.url().includes('/Support')) {
        await registerFirstSupportPasskeyForCurrentUser(page);
    } else {
        await registerFirstPasskeyForCurrentUser(page);
    }

    await gotoWhenReady(page, '/RosterWeeks', '#roster-content');
}
