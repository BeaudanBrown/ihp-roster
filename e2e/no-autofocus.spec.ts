import { expect, test, type Page } from '@playwright/test';
import { dialogOverlayMountDomId, timePickerTriggerDomAttr } from '../frontend/ts/generated/contracts';
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

    test('timesheet dialog initially focuses Shift Start', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');

        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');
        await page.locator('[data-timesheet-day-add="true"]').first().click();
        const form = page.locator('#timesheet-entry-create-form');
        await expect(form).toBeVisible();
        await expect(form.locator(`[${timePickerTriggerDomAttr}]`).first()).toBeFocused();
    });

    test('timesheet cards reserve their focus outline for keyboard focus', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');

        const cardLink = page.locator('.timesheet-entry-card-link').first();
        const card = cardLink.locator('..');
        await cardLink.scrollIntoViewIfNeeded();
        let reachedCardLink = false;
        for (let index = 0; index < 100; index += 1) {
            await page.keyboard.press('Tab');
            reachedCardLink = await cardLink.evaluate((link) => document.activeElement === link);
            if (reachedCardLink) break;
        }
        expect(reachedCardLink).toBe(true);
        await expect(cardLink).toBeFocused();
        await expect(card).toHaveCSS('outline-width', '2px');
        await cardLink.evaluate((link) => (link as HTMLElement).blur());

        const bounds = await cardLink.boundingBox();
        expect(bounds).not.toBeNull();

        await page.mouse.move((bounds?.x ?? 0) + 4, (bounds?.y ?? 0) + 4);
        await page.mouse.down();
        await expect(card).toHaveCSS('outline-width', '0px');
        await page.mouse.up();
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
