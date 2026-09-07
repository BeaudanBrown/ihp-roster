import { expect, test, type Page } from '@playwright/test';
import { dialogDismissedEvent, dialogOverlayMountDomId, dialogPointerDismissBlurDomAttr, timePickerTriggerDomAttr } from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady } from './support/runtime';
import { loginAs } from './support/session';
import { webauthnBaseURL } from './support/passkeys';

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

    test('timesheet dismissal blurs pointer-opened cards but preserves keyboard focus', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');

        const cardLink = page.locator('.timesheet-entry-card-link').first();
        await expect(cardLink).toHaveAttribute(dialogPointerDismissBlurDomAttr, 'true');
        await expect(page.locator(`.timesheet-entry-card-link:not([${dialogPointerDismissBlurDomAttr}])`)).toHaveCount(0);
        await expect(page.locator(`[${dialogPointerDismissBlurDomAttr}]:not(.timesheet-entry-card-link)`)).toHaveCount(0);
        const dispatchDismissal = async () => {
            await page.locator(`#${dialogOverlayMountDomId}`).evaluate((mount, eventName) => {
                mount.dispatchEvent(new CustomEvent(eventName, {
                    bubbles: true,
                    detail: { dialog: document.createElement('div'), replacement: null },
                }));
            }, dialogDismissedEvent);
            await page.evaluate(() => new Promise<void>((resolve) => requestAnimationFrame(() => resolve())));
        };

        await cardLink.focus();
        await cardLink.dispatchEvent('pointerdown');
        await dispatchDismissal();
        await expect(cardLink).not.toBeFocused();

        await cardLink.focus();
        await cardLink.dispatchEvent('pointerdown');
        await page.evaluate(() => document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })));
        await dispatchDismissal();
        await expect(cardLink).toBeFocused();
    });

    for (const scenario of ['next-frame', 'replacement', 'moved', 'disconnected', 'keyboard-before-frame', 'duplicate', 'ordinary', 'outside-pointer', 'new-launcher-before-frame'] as const) {
        test(`timesheet pointer-dismiss cleanup preserves ${scenario} behavior`, async ({ page }) => {
            await loginAs(page, 'e2e-test@example.com', 'test-password-123');
            await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');
            const result = await page.locator('.timesheet-entry-card-link').first().evaluate(async (element, { scenario, eventName, mountId }) => {
                const link = element as HTMLElement;
                const mount = document.getElementById(mountId)!;
                const ordinary = document.createElement('button');
                document.body.append(ordinary);
                const nextLauncher = link.cloneNode(true) as HTMLElement;
                if (scenario === 'new-launcher-before-frame') link.parentElement!.append(nextLauncher);
                const opened = scenario === 'ordinary' ? ordinary : link;
                const trigger = scenario === 'new-launcher-before-frame' ? nextLauncher : opened;
                const originalBlur = trigger.blur;
                let blurCount = 0;
                trigger.blur = () => { blurCount += 1; originalBlur.call(trigger); };
                opened.focus();
                opened.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
                if (scenario === 'outside-pointer') ordinary.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
                if (scenario === 'moved') ordinary.focus();
                if (scenario === 'disconnected') link.remove();
                const dialog = document.createElement('div');
                const dismiss = (replacement: Element | null) => mount.dispatchEvent(new CustomEvent(eventName, {
                    bubbles: true, detail: { dialog, replacement },
                }));
                dismiss(scenario === 'replacement' ? document.createElement('div') : null);
                if (scenario === 'duplicate') dismiss(null);
                if (scenario === 'new-launcher-before-frame') {
                    nextLauncher.focus();
                    nextLauncher.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
                }
                if (scenario === 'keyboard-before-frame') document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Shift', bubbles: true }));
                const immediateBlurCount = blurCount;
                await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
                const result = { immediateBlurCount, blurCount, triggerFocused: document.activeElement === trigger, otherFocused: document.activeElement === ordinary };
                trigger.blur = originalBlur;
                nextLauncher.remove();
                ordinary.remove();
                return result;
            }, { scenario, eventName: dialogDismissedEvent, mountId: dialogOverlayMountDomId });
            expect(result).toEqual({
                immediateBlurCount: 0,
                blurCount: ['next-frame', 'duplicate', 'outside-pointer', 'new-launcher-before-frame'].includes(scenario) ? 1 : 0,
                triggerFocused: scenario === 'replacement' || scenario === 'keyboard-before-frame' || scenario === 'ordinary',
                otherFocused: scenario === 'moved' || scenario === 'ordinary',
            });
        });
    }

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
