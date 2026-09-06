import { expect, test } from '@playwright/test';
import { E2E_TIMEOUT, gotoWhenReady, loginAs, loginAsPrivilegedUserWithSeededPasskeySession, runSql } from './test-helpers';

const itemId = 'fb505000-0000-4000-8000-000000000001';
const title = 'E2E moderated feedback';

test('moderates Feedback with actor and passive plain-fragment refreshes', async ({ page, browser }, testInfo) => {
    test.setTimeout(E2E_TIMEOUT.slowTest);
    runSql(`
        DELETE FROM user_feedback_items WHERE id = '${itemId}';
        INSERT INTO user_feedback_items (id, venue_id, submitted_by_user_id, title, content, support_note)
        SELECT '${itemId}', membership.venue_id, account.id, '${title}', 'A moderated suggestion.', 'Private retained provenance'
        FROM users account JOIN venue_memberships membership ON membership.user_id = account.id
        WHERE account.email = 'e2e-worker@example.com' LIMIT 1;
    `);
    const viewerContext = await browser.newContext();
    const viewer = await viewerContext.newPage();
    try {
        await loginAsPrivilegedUserWithSeededPasskeySession(page, 'e2e-super-admin@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Feedback', '#feedback-review');
        await loginAs(viewer, 'e2e-worker@example.com', 'test-password-123');
        await gotoWhenReady(viewer, '/Feedback', '#feedback-cards');
        await expect(viewer.locator('#feedback-cards')).not.toContainText(title);
        const card = page.locator('#feedback-review article').filter({ has: page.getByRole('heading', { name: title, exact: true }) });
        await expect(card.getByRole('button', { name: 'Publish', exact: true })).toBeVisible();
        const initialCount = Number(await page.locator('#feedback-desktop-count').textContent());
        expect(initialCount).toBeGreaterThan(0);
        expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
        await page.screenshot({ path: testInfo.outputPath('feedback-management.png'), fullPage: true });
        await testInfo.attach('Feedback management', { path: testInfo.outputPath('feedback-management.png'), contentType: 'image/png' });

        const publicRefetch = viewer.waitForResponse(response => response.url().includes('/ShowFeedbackBoard') && response.request().method() === 'GET');
        const actorMutation = page.waitForResponse(response => response.url().includes('/PublishFeedback') && response.request().method() === 'POST');
        await card.getByRole('button', { name: 'Publish', exact: true }).click();
        const mutation = await actorMutation;
        expect(mutation.status()).toBe(200);
        expect(mutation.headers()['hx-reswap']).toBe('none');
        const fragment = await publicRefetch;
        expect(fragment.status()).toBe(200);
        expect(await fragment.text()).not.toContain('hx-swap-oob');
        await expect(viewer.locator('#feedback-cards')).toContainText(title, { timeout: E2E_TIMEOUT.assertion });
        await expect(viewer.locator('#feedback-cards')).not.toContainText('Private retained provenance');
        await expect(viewer.locator('#feedback-cards')).not.toContainText('e2e-worker@example.com');
        await expect(page.locator('#feedback-desktop-count')).toHaveText(initialCount === 1 ? '' : String(initialCount - 1), { timeout: E2E_TIMEOUT.assertion });
        await expect(card.getByRole('button', { name: 'Publish', exact: true })).toHaveCount(0);

        await card.getByRole('link', { name: 'Edit', exact: true }).click();
        await expect(page.locator('#feedback-edit-form')).toBeVisible();
        await page.getByLabel('Description', { exact: true }).fill('Revised public description');
        await page.getByRole('button', { name: 'Save', exact: true }).click();
        await expect(page.locator('#dialog-overlay-mount')).toBeEmpty({ timeout: E2E_TIMEOUT.assertion });
        await expect(viewer.locator('#feedback-cards')).toContainText('Revised public description', { timeout: E2E_TIMEOUT.assertion });
        await expect(viewer.locator('#feedback-cards')).toContainText('1 votes');

        await card.locator('summary').filter({ hasText: /^Archive$/ }).click();
        await expect(card).toContainText('All votes will be removed.');
        await card.getByRole('button', { name: 'Confirm archive', exact: true }).click();
        await expect(viewer.locator('#feedback-cards')).not.toContainText(title, { timeout: E2E_TIMEOUT.assertion });
        await card.getByRole('button', { name: 'Restore', exact: true }).click();
        await expect(page.locator('#feedback-desktop-count')).toHaveText(String(initialCount), { timeout: E2E_TIMEOUT.assertion });
        await expect(card.getByRole('button', { name: 'Publish', exact: true })).toBeVisible();
        await expect(viewer.locator('#feedback-cards')).not.toContainText(title);
        await page.screenshot({ path: testInfo.outputPath('feedback-restored.png'), fullPage: true });
        await testInfo.attach('Feedback restored', { path: testInfo.outputPath('feedback-restored.png'), contentType: 'image/png' });
        await gotoWhenReady(page, '/Support', '#support-shell');
        await expect(page.locator('#support-shell')).not.toContainText(title);
        await expect(page.locator('#support-shell')).not.toContainText('Private retained provenance');
    } finally {
        await viewerContext.close();
        runSql(`DELETE FROM user_feedback_items WHERE id = '${itemId}';`);
    }
});
