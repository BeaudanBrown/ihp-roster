import { expect, test, type Page } from '@playwright/test';
import {
    dialogBackdropDomAttr,
    dialogCloseDomAttr,
    dialogDismissedEvent,
    dialogMountDomAttr,
    dialogOverlayMountDomId,
    dialogSubmitConfigDomAttr,
    dialogSubmitDomAttr,
    toastCloseDomAttr,
    toastConfigDomAttr,
    toastMountDomAttr,
    toastOverlayMountDomId,
} from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady, uniqueE2EValue } from './support/runtime';
import { loginAs } from './support/session';

const dialogHostSelector = `#${dialogOverlayMountDomId}`;
const dialogSelector = `${dialogHostSelector} [${dialogMountDomAttr}]`;
const toastHostSelector = `#${toastOverlayMountDomId}`;

async function observeDialogDismissals(page: Page) {
    await page.locator(dialogHostSelector).evaluate((host, eventName) => {
        host.setAttribute('data-e2e-dialog-dismissals', '0');
        document.addEventListener(eventName, () => {
            const count = Number(host.getAttribute('data-e2e-dialog-dismissals') ?? '0');
            host.setAttribute('data-e2e-dialog-dismissals', String(count + 1));
        });
    }, dialogDismissedEvent);
}

async function openFeedbackDialog(page: Page) {
    const launcher = page.getByRole('link', { name: 'Add feedback', exact: true });
    await expect(launcher).toBeVisible({ timeout: E2E_TIMEOUT.action });
    await launcher.click();
    await expect(page.locator(dialogSelector)).toBeVisible({ timeout: E2E_TIMEOUT.action });
}

test.describe('Generated overlay capability', () => {
    test.beforeEach(async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Feedback', '#feedback-cards');
    });

    test('preserves dialog submit, HTMX clear, body locking, toast, and accessibility behavior', async ({ page }) => {
        await observeDialogDismissals(page);
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

        await page.locator('#feedback-title').fill('Overlay submission');
        await page.locator('#feedback-content').fill(uniqueE2EValue('overlay-capability'));
        let releaseRequest: () => void = () => undefined;
        const requestGate = new Promise<void>((resolve) => {
            releaseRequest = resolve;
        });
        await page.route('**/CreateFeedback', async (route) => {
            await requestGate;
            await route.continue();
        });
        const requestPromise = page.waitForRequest((request) =>
            request.method() === 'POST' && request.url().includes('/CreateFeedback'),
        );
        const responsePromise = page.waitForResponse((response) =>
            response.request().method() === 'POST' && response.url().includes('/CreateFeedback'),
        );
        await submit.click();
        await requestPromise;
        await expect(dialog).toHaveAttribute('aria-busy', 'true');
        await expect(dialog.getByRole('status')).toContainText('Working...');
        await expect(dialog.getByRole('button')).toHaveCount(0);
        releaseRequest();
        const response = await responsePromise;
        expect(response.status(), await response.text()).toBe(200);

        await expect(page.locator(dialogHostSelector)).toBeEmpty({ timeout: E2E_TIMEOUT.assertion });
        await expect(page.locator(dialogHostSelector)).toHaveAttribute('data-e2e-dialog-dismissals', '1');
        await expect(page.locator('body')).not.toHaveClass(/modal-open/);

        const toast = page.locator(`${toastHostSelector} [${toastMountDomAttr}]`);
        await expect(toast).toContainText('Thanks — your feedback was submitted for review.', { timeout: E2E_TIMEOUT.assertion });
        const rawToastConfig = await toast.getAttribute(toastConfigDomAttr);
        expect(rawToastConfig).not.toBeNull();
        expect(JSON.parse(rawToastConfig!)).toEqual({ autoHideMs: 3200 });

        const toastClose = toast.locator(`[${toastCloseDomAttr}]`);
        await expect(toastClose).toHaveAttribute('aria-label', 'Dismiss');
        await toastClose.click();
        await expect(toast).toHaveCount(0, { timeout: E2E_TIMEOUT.action });
    });

    test('preserves exactly-once close-control, backdrop, and Escape dismissal', async ({ page }) => {
        await observeDialogDismissals(page);
        const dialogHost = page.locator(dialogHostSelector);

        await openFeedbackDialog(page);
        await page.locator(`${dialogSelector} [${dialogCloseDomAttr}]`).first().click();
        await expect(dialogHost).toBeEmpty({ timeout: E2E_TIMEOUT.action });
        await expect(dialogHost).toHaveAttribute('data-e2e-dialog-dismissals', '1');

        await openFeedbackDialog(page);
        await page.locator(`[${dialogBackdropDomAttr}]`).dispatchEvent('click');
        await expect(dialogHost).toBeEmpty({ timeout: E2E_TIMEOUT.action });
        await expect(dialogHost).toHaveAttribute('data-e2e-dialog-dismissals', '2');

        await openFeedbackDialog(page);
        await page.keyboard.press('Escape');
        await expect(dialogHost).toBeEmpty({ timeout: E2E_TIMEOUT.action });
        await expect(dialogHost).toHaveAttribute('data-e2e-dialog-dismissals', '3');
        await expect(page.locator('body')).not.toHaveClass(/modal-open/);
    });

    test('reveals and re-hides out-of-window select options from a controlling checkbox', async ({ page }) => {
        await openFeedbackDialog(page);
        const dialog = page.locator(dialogSelector);
        await dialog.locator('.modal-body').evaluate((body) => {
            body.insertAdjacentHTML('beforeend', `
                <label><input type="checkbox" aria-controls="period-window-fixture">Show past and future periods</label>
                <select id="period-window-fixture">
                    <option value="">Choose a period</option>
                    <option value="current">Current period</option>
                    <option value="past" hidden>Past period</option>
                </select>
            `);
        });

        const toggle = dialog.getByRole('checkbox', { name: 'Show past and future periods' });
        const select = dialog.locator('#period-window-fixture');
        const pastOption = select.locator('option[value="past"]');
        await expect(pastOption).toHaveAttribute('hidden', '');

        await toggle.check();
        await expect(toggle).toHaveAttribute('aria-expanded', 'true');
        await expect(pastOption).not.toHaveAttribute('hidden', '');
        await select.selectOption('past');

        await toggle.uncheck();
        await expect(toggle).toHaveAttribute('aria-expanded', 'false');
        await expect(pastOption).toHaveAttribute('hidden', '');
        await expect(select).toHaveValue('');
    });
});
