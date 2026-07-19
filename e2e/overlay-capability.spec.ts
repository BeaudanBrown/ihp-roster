import { expect, test, type Page } from '@playwright/test';
import {
    dialogBackdropDomAttr,
    dialogCloseDomAttr,
    dialogMountDomAttr,
    dialogOverlayMountDomId,
    dialogSubmitConfigDomAttr,
    dialogSubmitDomAttr,
    toastCloseDomAttr,
    toastConfigDomAttr,
    toastMountDomAttr,
    toastOverlayMountDomId,
} from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT, gotoWhenReady, loginAs, uniqueE2EValue } from './test-helpers';

const dialogHostSelector = `#${dialogOverlayMountDomId}`;
const dialogSelector = `${dialogHostSelector} [${dialogMountDomAttr}]`;
const toastHostSelector = `#${toastOverlayMountDomId}`;

async function openFeedbackDialog(page: Page) {
    const launcher = page.getByRole('button', { name: 'feedback', exact: true });
    await expect(launcher).toBeVisible({ timeout: E2E_TIMEOUT.action });
    await launcher.click();
    await expect(page.locator(dialogSelector)).toBeVisible({ timeout: E2E_TIMEOUT.action });
}

test.describe('Generated overlay capability', () => {
    test.beforeEach(async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/LeaveRequests', '#leave-requests-content');
    });

    test('preserves dialog submit, HTMX clear, body locking, toast, and accessibility behavior', async ({ page }) => {
        await openFeedbackDialog(page);

        const dialog = page.locator(dialogSelector);
        await expect(dialog).toHaveAttribute('role', 'dialog');
        await expect(dialog).toHaveAttribute('aria-modal', 'true');
        await expect(dialog).toHaveAttribute('aria-labelledby', 'dialog-overlay-title');
        await expect(page.locator('body')).toHaveClass(/modal-open/);

        const submit = dialog.locator(`[${dialogSubmitDomAttr}]`);
        await expect(submit).toHaveCount(1);
        const rawSubmitConfig = await submit.getAttribute(dialogSubmitConfigDomAttr);
        expect(rawSubmitConfig).not.toBeNull();
        expect(JSON.parse(rawSubmitConfig!)).toEqual({ loadingLabel: 'Working...' });

        await page.locator('#feedback-content').fill(uniqueE2EValue('overlay-capability'));
        const responsePromise = page.waitForResponse((response) =>
            response.request().method() === 'POST' && response.url().includes('/CreateFeedback'),
        );
        await submit.click();
        const response = await responsePromise;
        expect(response.status(), await response.text()).toBe(200);

        await expect(page.locator(dialogHostSelector)).toBeEmpty({ timeout: E2E_TIMEOUT.assertion });
        await expect(page.locator('body')).not.toHaveClass(/modal-open/);

        const toast = page.locator(`${toastHostSelector} [${toastMountDomAttr}]`);
        await expect(toast).toContainText('Thanks — your feedback was sent.', { timeout: E2E_TIMEOUT.assertion });
        const rawToastConfig = await toast.getAttribute(toastConfigDomAttr);
        expect(rawToastConfig).not.toBeNull();
        expect(JSON.parse(rawToastConfig!)).toEqual({ autoHideMs: 3200 });

        const toastClose = toast.locator(`[${toastCloseDomAttr}]`);
        await expect(toastClose).toHaveAttribute('aria-label', 'Dismiss');
        await toastClose.click();
        await expect(toast).toHaveCount(0, { timeout: E2E_TIMEOUT.action });
    });

    test('preserves close-control, backdrop, and Escape dismissal', async ({ page }) => {
        await openFeedbackDialog(page);
        await page.locator(`${dialogSelector} [${dialogCloseDomAttr}]`).first().click();
        await expect(page.locator(dialogHostSelector)).toBeEmpty({ timeout: E2E_TIMEOUT.action });

        await openFeedbackDialog(page);
        await page.locator(`[${dialogBackdropDomAttr}]`).dispatchEvent('click');
        await expect(page.locator(dialogHostSelector)).toBeEmpty({ timeout: E2E_TIMEOUT.action });

        await openFeedbackDialog(page);
        await page.keyboard.press('Escape');
        await expect(page.locator(dialogHostSelector)).toBeEmpty({ timeout: E2E_TIMEOUT.action });
        await expect(page.locator('body')).not.toHaveClass(/modal-open/);
    });
});
