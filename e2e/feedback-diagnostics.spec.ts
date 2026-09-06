import { expect, test } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady, uniqueE2EValue } from './support/runtime';
import { loginAs } from './support/session';
import { runSql } from './support/database';

test.describe('Private Feedback submission', () => {
    test('navigates to the board and submits only editorial fields for review', async ({ page }, testInfo) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Feedback', '#feedback-cards');
        const title = uniqueE2EValue('private-title');
        await expect(page.getByRole('heading', { name: 'Feedback', exact: true })).toBeVisible();
        expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
        await page.screenshot({ path: testInfo.outputPath('feedback-board.png'), fullPage: true });
        await testInfo.attach('Feedback board', { path: testInfo.outputPath('feedback-board.png'), contentType: 'image/png' });
        await page.getByRole('link', { name: 'Add feedback', exact: true }).click();
        await expect(page.locator('#feedback-form')).toBeVisible({ timeout: E2E_TIMEOUT.action });
        await page.getByLabel('Title', { exact: true }).fill(title);
        await page.getByLabel('Description', { exact: true }).fill('A private suggestion for review.');
        await page.screenshot({ path: testInfo.outputPath('feedback-dialog.png'), fullPage: true });
        await testInfo.attach('Feedback dialog', { path: testInfo.outputPath('feedback-dialog.png'), contentType: 'image/png' });
        const requestPromise = page.waitForRequest((request) =>
            request.method() === 'POST' && request.url().includes('/CreateFeedback'),
        );
        await page.getByRole('button', { name: 'Save', exact: true }).click();
        const request = await requestPromise;
        const params = new URLSearchParams(request.postData() ?? '');
        expect([...params.keys()].sort()).toEqual(['content', 'feedbackTitle', 'feedbackType']);
        await expect(page.locator('#dialog-overlay-mount')).toBeEmpty({ timeout: E2E_TIMEOUT.assertion });
        await expect(page.getByText('Thanks — your feedback was submitted for review.', { exact: true })).toBeVisible();
        await gotoWhenReady(page, '/Feedback', '#feedback-cards');
        await expect(page.locator('#feedback-cards')).not.toContainText(title);
    });

    test('renders responsive public cards without private provenance', async ({ page }, testInfo) => {
        const itemId = 'fb504000-0000-4000-8000-000000000001';
        runSql(`
            DELETE FROM user_feedback_items WHERE id = '${itemId}';
            INSERT INTO user_feedback_items (id, venue_id, submitted_by_user_id, title, content, lifecycle, published_at, published_by_user_id, support_note, submitted_path)
            SELECT '${itemId}', membership.venue_id, account.id,
                'A shared improvement for everyone', 'Long description: ${'unbroken'.repeat(30)}',
                'public', '2026-09-01 12:00:00+00', account.id, 'Secret retained note', '/private-origin'
            FROM users AS account JOIN venue_memberships AS membership ON membership.user_id = account.id
            WHERE account.email = 'e2e-test@example.com' LIMIT 1;
        `);
        try {
            await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
            await gotoWhenReady(page, '/Feedback', '#feedback-cards');
            const cards = page.locator('#feedback-cards');
            await expect(cards.getByRole('heading', { name: 'A shared improvement for everyone' })).toBeVisible();
            for (const secret of ['Secret retained note', '/private-origin', 'e2e-test@example.com']) {
                await expect(cards).not.toContainText(secret);
            }
            expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
            await page.screenshot({ path: testInfo.outputPath('feedback-public.png'), fullPage: true });
            await testInfo.attach('Public Feedback cards', { path: testInfo.outputPath('feedback-public.png'), contentType: 'image/png' });
        } finally {
            runSql(`DELETE FROM user_feedback_items WHERE id = '${itemId}';`);
        }
    });

    test('submits successfully without JavaScript and keeps the submission private', async ({ browser, page }) => {
        test.setTimeout(E2E_TIMEOUT.slowTest);
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        const cookies = await page.context().cookies();
        const context = await browser.newContext({ javaScriptEnabled: false });
        await context.addCookies(cookies);
        const nativePage = await context.newPage();
        try {
            // The ordinary session above warmed the runtime. A no-JS browser
            // cannot acknowledge the live subscriptions awaited by gotoWhenReady.
            await nativePage.goto('/Feedback');
            await expect(nativePage.locator('#feedback-cards')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
            await nativePage.getByRole('link', { name: 'Add feedback', exact: true }).click();
            await expect(nativePage.locator('#feedback-form')).toBeVisible();
            const title = uniqueE2EValue('feedback-native');
            await nativePage.getByLabel('Title', { exact: true }).fill(title);
            await nativePage.getByLabel('Description', { exact: true }).fill('Native submission remains private.');
            await nativePage.locator('button[type="submit"][form="feedback-form"]').click();
            await expect(nativePage).toHaveURL(/\/Feedback$/, { timeout: E2E_TIMEOUT.navigation });
            await expect(nativePage.locator('#feedback-cards')).toBeVisible();
            await expect(nativePage.locator('#feedback-cards')).not.toContainText(title);
        } finally {
            await context.close();
        }
    });
});
