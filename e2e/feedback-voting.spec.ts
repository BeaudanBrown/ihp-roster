import { expect, test } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady } from './support/runtime';
import { loginAs } from './support/session';
import { runSql } from './support/database';

const targetId = 'fb506000-0000-4000-8000-000000000001';
const targetTitle = 'E2E vote ordering 1';
const prefix = 'fb506000-0000-4000-8000-';

test('vote toggles reorder actor and passive cards while preserving keyboard focus and viewport', async ({ page, browser }, testInfo) => {
    test.setTimeout(E2E_TIMEOUT.slowTest);
    runSql(`
        DELETE FROM user_feedback_items WHERE id::text LIKE '${prefix}%';
        INSERT INTO user_feedback_items (id, venue_id, submitted_by_user_id, title, content, lifecycle, published_at, published_by_user_id)
        SELECT ('${prefix}' || lpad(n::text, 12, '0'))::uuid, membership.venue_id, account.id,
               'E2E vote ordering ' || n, repeat('Shared global feedback description. ', 8), 'public',
               '2026-09-01'::timestamptz + n * interval '1 minute', account.id
        FROM generate_series(1, 12) n CROSS JOIN users account
        JOIN venue_memberships membership ON membership.user_id = account.id
        WHERE account.email = 'e2e-worker@example.com';
        INSERT INTO feedback_votes (feedback_item_id, user_id)
        SELECT item.id, account.id FROM user_feedback_items item CROSS JOIN users account
        WHERE item.id::text LIKE '${prefix}%' AND account.email = 'e2e-worker@example.com';
        INSERT INTO feedback_votes (feedback_item_id, user_id)
        SELECT item.id, account.id FROM user_feedback_items item CROSS JOIN users account
        WHERE item.id::text IN ('${prefix}000000000011', '${prefix}000000000012')
          AND account.email IN ('e2e-admin@example.com', 'e2e-super-admin@example.com');
    `);
    const viewerContext = await browser.newContext({ viewport: page.viewportSize() ?? undefined });
    const viewer = await viewerContext.newPage();
    try {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Feedback', '#feedback-cards');
        await loginAs(viewer, 'e2e-admin@example.com', 'test-password-123');
        await gotoWhenReady(viewer, '/Feedback', '#feedback-cards');
        const actorButton = page.getByRole('button', { name: `Vote for ${targetTitle}`, exact: true });
        const passiveButton = viewer.getByRole('button', { name: `Vote for ${targetTitle}`, exact: true });
        const card = (owner: typeof page) => owner.locator('#feedback-cards article').filter({ has: owner.getByRole('heading', { name: targetTitle, exact: true }) });
        const headings = (owner: typeof page) => owner.locator('#feedback-cards article h2').filter({ hasText: /^E2E vote ordering / });
        await expect(headings(page).last()).toHaveText(targetTitle);
        for (const button of [actorButton, passiveButton]) {
            await button.scrollIntoViewIfNeeded();
            await button.focus();
        }
        const actorTop = (await actorButton.boundingBox())!.y;
        const passiveTop = (await passiveButton.boundingBox())!.y;
        let documentRequests = 0;
        page.on('request', request => { if (request.resourceType() === 'document') documentRequests += 1; });
        const actorFragment = page.waitForResponse(response => response.url().includes('/ShowFeedbackBoard') && response.request().method() === 'GET');
        const passiveFragment = viewer.waitForResponse(response => response.url().includes('/ShowFeedbackBoard') && response.request().method() === 'GET');
        await actorButton.press('Space');
        for (const response of [await actorFragment, await passiveFragment]) {
            expect(response.status()).toBe(200);
            expect(await response.text()).not.toContain('hx-swap-oob');
        }
        await expect(actorButton).toHaveAttribute('aria-pressed', 'true');
        await expect(passiveButton).toHaveAttribute('aria-pressed', 'false');
        for (const owner of [page, viewer]) {
            await expect(card(owner)).toContainText('2 votes');
            await expect(headings(owner).nth(2)).toHaveText(targetTitle);
            await expect(card(owner)).toHaveCount(1);
            expect(await owner.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
        }
        await expect(actorButton).toBeFocused();
        await expect(passiveButton).toBeFocused();
        expect(Math.abs((await actorButton.boundingBox())!.y - actorTop)).toBeLessThan(4);
        expect(Math.abs((await passiveButton.boundingBox())!.y - passiveTop)).toBeLessThan(4);
        await page.screenshot({ path: testInfo.outputPath('feedback-vote-rank.png') });
        await testInfo.attach('Vote rank and focus', { path: testInfo.outputPath('feedback-vote-rank.png'), contentType: 'image/png' });
        await actorButton.press('Enter');
        await expect(actorButton).toHaveAttribute('aria-pressed', 'false');
        for (const owner of [page, viewer]) {
            await expect(card(owner)).toContainText('1 votes');
            await expect(headings(owner).last()).toHaveText(targetTitle);
        }
        await expect(actorButton).toBeFocused();
        expect(documentRequests).toBe(0);
        const invalidMethod = await page.request.get(`/VoteFeedback?feedbackItemId=${targetId}`);
        expect([404, 405]).toContain(invalidMethod.status());
    } finally {
        await viewerContext.close();
        runSql(`DELETE FROM user_feedback_items WHERE id::text LIKE '${prefix}%';`);
    }
});
