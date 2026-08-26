import { expect, test } from '@playwright/test';
import {
    dialogMountDomAttr,
    pageReadyEvent,
    passkeyActionButtonDomAttr,
    passkeyDismissalDomAttr,
    passkeyFlowConfigDomAttr,
    passkeyLoginDomAttr,
    parsePasskeyFlowConfig,
    passkeySetupPromptDomAttr,
    passkeyStatusDomAttr,
    toastMountDomAttr,
    toastOverlayMountDomId,
} from '../frontend/ts/generated/contracts';
import { localStorageKeyForPasskey } from '../frontend/ts/passkeys/storage';
import { E2E_TIMEOUT } from './timeouts';
import {
    clearE2EUserPasskeys,
    enableVirtualPasskeyAuthenticator,
    gotoWhenReady,
    loginAsPrivilegedUserWithFreshPasskey,
    loginAsWithFreshBrowserSession,
    openProfileSecuritySection,
    registerFirstPasskeyForCurrentUser,
    removeVirtualPasskeyAuthenticator,
    resetE2EUserPasskeySignCount,
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

test.describe('Venue-admin passkeys', () => {
    test.setTimeout(E2E_TIMEOUT.slowTest);

    test('malformed generated flow config is diagnosed without mutating server HTML', async ({ page }) => {
        await gotoWhenReady(page, '/NewSession', '#email');

        const result = await page.evaluate((contract) => {
            const original = document.querySelector<HTMLElement>(`[${contract.passkeyLoginDomAttr}]`);
            if (original === null) throw new Error('Missing rendered passkey login control');

            const fixture = document.createElement('div');
            fixture.innerHTML = original.outerHTML;
            document.body.append(fixture);

            const root = fixture.querySelector<HTMLElement>(`[${contract.passkeyLoginDomAttr}]`);
            if (root === null) throw new Error('Missing cloned passkey login control');
            const rawConfig = root.getAttribute(contract.passkeyFlowConfigDomAttr);
            if (rawConfig === null) throw new Error('Missing rendered passkey flow config');
            root.setAttribute(
                contract.passkeyFlowConfigDomAttr,
                JSON.stringify({ ...JSON.parse(rawConfig), extra: true }),
            );

            const diagnostics: Array<{ code?: string; message?: string }> = [];
            const originalConsoleError = console.error;
            console.error = (message?: unknown, diagnostic?: unknown) => {
                if (message === 'Invalid generated passkey configuration' && typeof diagnostic === 'object' && diagnostic !== null) {
                    diagnostics.push(diagnostic as { code?: string; message?: string });
                }
                originalConsoleError(message, diagnostic);
            };

            const before = root.outerHTML;
            document.dispatchEvent(new CustomEvent(contract.pageReadyEvent, { detail: { target: fixture } }));
            const after = root.outerHTML;
            console.error = originalConsoleError;

            const action = root.querySelector<HTMLButtonElement>(`[${contract.passkeyActionButtonDomAttr}]`);
            const status = root.querySelector<HTMLElement>(`[${contract.passkeyStatusDomAttr}]`);
            return {
                before,
                after,
                diagnostics,
                actionDisabled: action?.disabled ?? null,
                statusText: status?.textContent ?? null,
            };
        }, {
            pageReadyEvent,
            passkeyActionButtonDomAttr,
            passkeyFlowConfigDomAttr,
            passkeyLoginDomAttr,
            passkeyStatusDomAttr,
        });

        expect(result.after).toBe(result.before);
        expect(result.actionDisabled).toBe(false);
        expect(result.statusText).toBe('');
        expect(result.diagnostics).toEqual([
            expect.objectContaining({ code: 'invalid-flow-config' }),
        ]);
    });

    test('malformed begin envelopes are rejected before invoking the credential API', async ({ page }) => {
        await page.route('**/BeginPasskeyAuthentication', async (route) => {
            await route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify({
                    challenge: 'AQID',
                    timeout: 60_000,
                    rpId: 'localhost',
                    allowCredentials: [],
                    userVerification: 'preferred',
                    extra: true,
                }),
            });
        });
        await gotoWhenReady(page, '/NewSession', '#email');
        await page.evaluate(() => {
            const state = globalThis as typeof globalThis & { __passkeyCredentialGetCalls?: number };
            state.__passkeyCredentialGetCalls = 0;
            Object.defineProperty(navigator.credentials, 'get', {
                configurable: true,
                value: async () => {
                    state.__passkeyCredentialGetCalls = (state.__passkeyCredentialGetCalls ?? 0) + 1;
                    return null;
                },
            });
        });

        await page.locator(`[${passkeyLoginDomAttr}] [${passkeyActionButtonDomAttr}]`).click();

        await expect(page.locator(`[${passkeyLoginDomAttr}] [${passkeyStatusDomAttr}]`))
            .toHaveText('Passkey request failed.', { timeout: E2E_TIMEOUT.assertion });
        expect(await page.evaluate(() => (
            globalThis as typeof globalThis & { __passkeyCredentialGetCalls?: number }
        ).__passkeyCredentialGetCalls)).toBe(0);
        await expect(page).toHaveURL(/NewSession/);
    });

    test('malformed redirect errors are rejected without navigating', async ({ page }) => {
        await page.route('**/BeginPasskeyAuthentication', async (route) => {
            await route.fulfill({
                status: 403,
                contentType: 'application/json',
                body: JSON.stringify({
                    error: 'legacy compatibility envelope',
                    redirectTo: '/Admin',
                }),
            });
        });
        await gotoWhenReady(page, '/NewSession', '#email');

        await page.locator(`[${passkeyLoginDomAttr}] [${passkeyActionButtonDomAttr}]`).click();

        await expect(page.locator(`[${passkeyLoginDomAttr}] [${passkeyStatusDomAttr}]`))
            .toHaveText('Passkey request failed.', { timeout: E2E_TIMEOUT.assertion });
        await expect(page).toHaveURL(/NewSession/);
    });

    test('setup prompt Escape dismissal delegates overlay lifecycle and persists the UX hint', async ({ page }) => {
        clearE2EUserPasskeys(adminEmail);
        await passwordLogin(page);

        const prompt = page.locator(`[${passkeySetupPromptDomAttr}]`).first();
        const dialog = prompt.locator(`[${dialogMountDomAttr}]`);
        await expect(dialog).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(prompt.locator(`[${passkeyDismissalDomAttr}]`)).toBeVisible();
        await expect(page.locator('body')).toHaveClass(/modal-open/);
        await expect(page.locator('body')).toHaveCSS('overflow', 'hidden');

        const rawConfig = await prompt.getAttribute(passkeyFlowConfigDomAttr);
        if (rawConfig === null) throw new Error('Missing setup-prompt configuration');
        const config = parsePasskeyFlowConfig(JSON.parse(rawConfig));
        if (config.tag !== 'setup-prompt') throw new Error('Expected setup-prompt configuration');
        const dismissalKey = localStorageKeyForPasskey(config.promptUserKey, 'passkeyPromptDismissedUntil');

        await page.keyboard.press('Escape');

        await expect(dialog).toHaveCount(0, { timeout: E2E_TIMEOUT.action });
        await expect(page.locator('body')).not.toHaveClass(/modal-open/);
        await expect(page.locator('body')).not.toHaveCSS('overflow', 'hidden');
        const dismissedUntil = await page.evaluate((key) => Number(localStorage.getItem(key) || '0'), dismissalKey);
        expect(dismissedUntil).toBeGreaterThan(Date.now());
    });

    test('password login lets venue admins use roster and admin pages when strong auth is optional', async ({ page }) => {
        clearE2EUserPasskeys(adminEmail);

        await passwordLogin(page);

        await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWindow)/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await gotoWhenReady(page, '/Admin', '#admin-config-sections');
        await expect(page.locator('#admin-config-sections')).toBeVisible();
    });

    test('venue admin can register the first passkey and access admin pages', async ({ page }) => {
        await loginAsPrivilegedUserWithFreshPasskey(page);

        await gotoWhenReady(page, '/Admin', '#admin-config-sections');

        await expect(page.locator('#admin-config-sections')).toBeVisible();
        await expect(page.getByRole('button', { name: 'Roster Groups' }).first()).toBeVisible();
        await expect(page.getByRole('button', { name: 'Roster Groups' }).first()).toHaveAttribute('aria-expanded', 'false');
    });

    test('password login uses immediate in-place passkey step-up without replaying the protected action', async ({ page }) => {
        await loginAsPrivilegedUserWithFreshPasskey(page);
        await logout(page);

        await loginAsWithFreshBrowserSession(page, adminEmail, password);
        await openProfileSecuritySection(page);
        const profileUrl = page.url();
        const beginStepUpResponse = page.waitForResponse(
            (response) => new URL(response.url()).pathname === '/BeginPasskeyStepUpAuthentication',
            { timeout: E2E_TIMEOUT.passkey },
        );
        await page.getByRole('button', { name: 'Email setup link for another device' }).click();
        expect((await beginStepUpResponse).status()).toBe(200);
        await expect(page.locator(`[${dialogMountDomAttr}]`)).toHaveCount(0, { timeout: E2E_TIMEOUT.passkey });
        expect(page.url()).toBe(profileUrl);
        const queuedToast = page.locator(`#${toastOverlayMountDomId} [${toastMountDomAttr}]`).filter({ hasText: 'New-device passkey setup email queued.' });
        await expect(queuedToast).toHaveCount(0);

        await page.getByRole('button', { name: 'Email setup link for another device' }).click();
        await expect(queuedToast).toContainText('New-device passkey setup email queued. It should arrive shortly; open it on the device you want to add.', { timeout: E2E_TIMEOUT.navigation });
    });

    test('in-place step-up keeps an explicit fallback and cancellation never runs the protected action', async ({ page }) => {
        await loginAsPrivilegedUserWithFreshPasskey(page);
        await logout(page);

        await loginAsWithFreshBrowserSession(page, adminEmail, password);
        await openProfileSecuritySection(page);
        const profileUrl = page.url();
        await page.evaluate(() => {
            Object.defineProperty(window, 'PublicKeyCredential', { configurable: true, value: undefined });
        });

        await page.getByRole('button', { name: 'Email setup link for another device' }).click();
        const dialog = page.locator(`[${dialogMountDomAttr}]`);
        await expect(dialog).toBeVisible({ timeout: E2E_TIMEOUT.action });
        await expect(dialog).toContainText('Passkeys are not supported in this browser.');
        const fallback = dialog.getByRole('button', { name: 'Verify with passkey' });
        await expect(fallback).toBeEnabled();
        await fallback.click();
        await expect(dialog).toContainText('Passkeys are not supported in this browser.');
        await dialog.getByRole('button', { name: 'Cancel' }).click();

        await expect(dialog).toHaveCount(0);
        expect(page.url()).toBe(profileUrl);
        const queuedToast = page.locator(`#${toastOverlayMountDomId} [${toastMountDomAttr}]`).filter({ hasText: 'New-device passkey setup email queued.' });
        await expect(queuedToast).toHaveCount(0);
    });

    test('passkey login marks venue-admin access as freshly verified', async ({ page }) => {
        await loginAsPrivilegedUserWithFreshPasskey(page);
        resetE2EUserPasskeySignCount(adminEmail);
        await logout(page);

        await gotoWhenReady(page, '/NewSession', '#email');
        await page.getByRole('button', { name: 'Sign in with a passkey' }).click();
        await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWindow)/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });

        await gotoWhenReady(page, '/Admin', '#admin-config-sections');
        await expect(page.locator('#admin-config-sections')).toBeVisible();
    });

    test('venue admin can delete their last passkey after fresh verification when strong auth is optional', async ({ page }) => {
        await loginAsPrivilegedUserWithFreshPasskey(page);
        await openProfileSecuritySection(page);
        await expect(page.locator('#profile-security-collapse table')).toBeVisible();

        page.once('dialog', async (dialog) => {
            expect(dialog.message()).toContain('Delete this passkey?');
            await dialog.accept();
        });
        await page.getByRole('button', { name: 'Delete' }).first().click();

        await expect(page).toHaveURL(/EditProfile/, { timeout: E2E_TIMEOUT.navigation });
        await openProfileSecuritySection(page);
        await expect(page.locator('#profile-security-collapse table tbody tr')).toHaveCount(0);
        await expect(page.locator('body')).toContainText('No passkeys registered yet.');
    });

    test('adding another admin passkey uses the emailed setup-link path after password login', async ({ page }) => {
        clearE2EUserPasskeys(adminEmail);
        const firstAuthenticator = await enableVirtualPasskeyAuthenticator(page);

        await passwordLogin(page);
        await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWindow)/, { timeout: E2E_TIMEOUT.navigation });
        await registerFirstPasskeyForCurrentUser(page);
        await logout(page);

        await loginAsWithFreshBrowserSession(page, adminEmail, password);
        await openProfileSecuritySection(page);
        await expect(page.getByRole('link', { name: 'Create passkey' })).toHaveCount(0);
        const profileUrl = page.url();
        const beginStepUpResponse = page.waitForResponse(
            (response) => new URL(response.url()).pathname === '/BeginPasskeyStepUpAuthentication',
            { timeout: E2E_TIMEOUT.passkey },
        );
        await page.getByRole('button', { name: 'Email setup link for another device' }).click();
        expect((await beginStepUpResponse).status()).toBe(200);
        await expect(page.locator(`[${dialogMountDomAttr}]`)).toHaveCount(0, { timeout: E2E_TIMEOUT.passkey });
        expect(page.url()).toBe(profileUrl);
        const queuedToast = page.locator(`#${toastOverlayMountDomId} [${toastMountDomAttr}]`).filter({ hasText: 'New-device passkey setup email queued.' });
        await expect(queuedToast).toHaveCount(0);

        await page.getByRole('button', { name: 'Email setup link for another device' }).click();
        await expect(queuedToast).toContainText('New-device passkey setup email queued. It should arrive shortly; open it on the device you want to add.', { timeout: E2E_TIMEOUT.navigation });
        await removeVirtualPasskeyAuthenticator(firstAuthenticator);
    });
});
