import { expect, test, type Page } from '@playwright/test';
import { dialogOverlayMountDomId } from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from './timeouts';
import {
    gotoWhenReady,
    loginAs,
    webauthnBaseURL,
} from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

const controlSelector = 'input:not([type="hidden"]), select, textarea, button, a[href]';

async function focusedControl(page: Page, scopeSelector = 'body') {
    return page.evaluate(({ scopeSelector, controlSelector }) => {
        const scope = document.querySelector(scopeSelector);
        const active = document.activeElement;

        if (!(scope instanceof HTMLElement) || !(active instanceof HTMLElement)) {
            return null;
        }

        if (!scope.contains(active) || !active.matches(controlSelector)) {
            return null;
        }

        return {
            tagName: active.tagName,
            id: active.id,
            name: active.getAttribute('name'),
            text: active.textContent?.trim().slice(0, 80) ?? '',
        };
    }, { scopeSelector, controlSelector });
}

async function expectNoFocusedControl(page: Page, scopeSelector = 'body') {
    await expect.poll(() => focusedControl(page, scopeSelector), {
        timeout: E2E_TIMEOUT.action,
        message: `expected no focused form/button/link control in ${scopeSelector}`,
    }).toBeNull();
}

test.describe('No automatic focus', () => {
    test('public sign-in page does not focus a control on load', async ({ page }) => {
        await gotoWhenReady(page, '/NewSession', '#email');
        await expectNoFocusedControl(page);
    });

    test('profile form does not focus a control on load', async ({ page }) => {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await gotoWhenReady(page, '/EditProfile', '#profile-content-fragment');
        await expectNoFocusedControl(page);
    });

    test('timesheet dialog does not focus controls when opened', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');

        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');
        await page.locator('[data-timesheet-day-add="true"]').first().click();
        await expect(page.locator('#timesheet-entry-create-form')).toBeVisible();
        await expectNoFocusedControl(page, `#${dialogOverlayMountDomId}`);
    });

    test('leave dialog does not focus controls when opened', async ({ page }) => {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await gotoWhenReady(page, '/EditProfile', '#profile-content-fragment');

        await page.evaluate((dialogTarget) => {
            const htmx = (window as Window & { htmx?: { ajax: (method: string, url: string, options: { target: string; swap: string }) => unknown } }).htmx;
            if (!htmx) throw new Error('Expected htmx runtime');
            htmx.ajax('GET', '/NewLeaveRequest', { target: dialogTarget, swap: 'innerHTML' });
        }, `#${dialogOverlayMountDomId}`);
        await expect(page.locator('#leave-request-form')).toBeVisible();
        await expectNoFocusedControl(page, `#${dialogOverlayMountDomId}`);
    });

    test('passkey setup page does not focus controls when shown', async ({ page }) => {
        await loginAs(page, 'e2e-admin@example.com', 'test-password-123');
        await page.goto('/PasskeySetup');
        await expect(page).toHaveURL(/PasskeySetup/, { timeout: E2E_TIMEOUT.navigation });
        await expectNoFocusedControl(page);
    });
});
