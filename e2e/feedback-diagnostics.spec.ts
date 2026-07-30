import { expect, test } from '@playwright/test';
import {
    feedbackDevicePixelRatioInputDomAttr,
    feedbackDisplayModeInputDomAttr,
    feedbackViewportHeightInputDomAttr,
    feedbackViewportWidthInputDomAttr,
} from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT, gotoWhenReady, loginAs, uniqueE2EValue } from './test-helpers';

const diagnosticSelectors = {
    viewportWidth: `[${feedbackViewportWidthInputDomAttr}]`,
    viewportHeight: `[${feedbackViewportHeightInputDomAttr}]`,
    devicePixelRatio: `[${feedbackDevicePixelRatioInputDomAttr}]`,
    displayMode: `[${feedbackDisplayModeInputDomAttr}]`,
};

test.describe('Feedback diagnostics', () => {
    test('submits bounded browser diagnostics for the originating page', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/LeaveRequests?feedbackToken=must-not-be-collected', '#leave-requests-content');

        await page.getByRole('button', { name: 'feedback', exact: true }).click();
        await expect(page.locator('#feedback-form')).toBeVisible({ timeout: E2E_TIMEOUT.action });

        const viewport = page.viewportSize();
        expect(viewport).not.toBeNull();
        await expect(page.locator(diagnosticSelectors.viewportWidth)).toHaveValue(String(viewport!.width));
        await expect(page.locator(diagnosticSelectors.viewportHeight)).toHaveValue(String(viewport!.height));
        await expect(page.locator(diagnosticSelectors.displayMode)).toHaveValue('browser');

        const expectedPixelRatio = await page.evaluate(() => String(window.devicePixelRatio));
        await expect(page.locator(diagnosticSelectors.devicePixelRatio)).toHaveValue(expectedPixelRatio);

        await page.locator('#feedback-content').fill(uniqueE2EValue('feedback-diagnostics'));
        const requestPromise = page.waitForRequest((request) =>
            request.method() === 'POST' && request.url().includes('/CreateFeedback'),
        );
        await page.getByRole('button', { name: 'Save', exact: true }).click();
        const request = await requestPromise;
        const params = new URLSearchParams(request.postData() ?? '');

        expect(new URL(request.headers()['referer']).pathname).toBe('/LeaveRequests');
        expect(params.get('feedbackViewportWidth')).toBe(String(viewport!.width));
        expect(params.get('feedbackViewportHeight')).toBe(String(viewport!.height));
        expect(params.get('feedbackDevicePixelRatio')).toBe(expectedPixelRatio);
        expect(params.get('feedbackDisplayMode')).toBe('browser');
    });

    test('submits successfully without JavaScript or diagnostics', async ({ browser, page }) => {
        test.setTimeout(E2E_TIMEOUT.slowTest);
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        const cookies = await page.context().cookies();
        const noJavaScriptContext = await browser.newContext({ javaScriptEnabled: false });
        await noJavaScriptContext.addCookies(cookies);
        const noJavaScriptPage = await noJavaScriptContext.newPage();

        try {
            await gotoWhenReady(noJavaScriptPage, '/NewFeedback', '#feedback-form');
            await expect(noJavaScriptPage.locator(diagnosticSelectors.viewportWidth)).toHaveValue('');
            await expect(noJavaScriptPage.locator(diagnosticSelectors.viewportHeight)).toHaveValue('');
            await expect(noJavaScriptPage.locator(diagnosticSelectors.devicePixelRatio)).toHaveValue('');
            await expect(noJavaScriptPage.locator(diagnosticSelectors.displayMode)).toHaveValue('');

            await noJavaScriptPage.locator('#feedback-content').fill(uniqueE2EValue('feedback-no-js'));
            await noJavaScriptPage.locator('button[type="submit"][form="feedback-form"]').click();

            await expect(noJavaScriptPage).toHaveURL(/(RosterWeeks|ShowRosterWeek)/, { timeout: E2E_TIMEOUT.navigation });
            await expect(noJavaScriptPage.locator('#feedback-form')).toHaveCount(0, { timeout: E2E_TIMEOUT.assertion });
        } finally {
            await noJavaScriptContext.close();
        }
    });
});
