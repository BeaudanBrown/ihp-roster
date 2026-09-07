import { expect, test, type Page } from '@playwright/test';
import { E2E_TIMEOUT, gotoWhenReady, loginAs, loginAsPrivilegedUserWithSeededPasskeySession, querySql, runSql, uniqueE2EValue } from './test-helpers';

const voterId = 'fb507000-0000-4000-8000-000000000001';
const privateId = 'fb507000-0000-4000-8000-000000000002';
const archivedId = 'fb507000-0000-4000-8000-000000000003';
const voterEmail = 'e2e-507-cross-venue@example.com';

test('complete moderated journey preserves private data and private-only live activity', async ({ page, browser }, testInfo) => {
    test.setTimeout(E2E_TIMEOUT.slowTest);
    const title = uniqueE2EValue('E2E Feedback journey');
    runSql(`
        INSERT INTO users (id, email, password_hash, user_role, is_profile_completed, email_verified_at)
        SELECT '${voterId}', '${voterEmail}', password_hash, 'staff', true, NOW() FROM users WHERE email = 'e2e-worker@example.com'
        ON CONFLICT (id) DO NOTHING;
        INSERT INTO venue_memberships (venue_id, user_id, venue_role)
        VALUES ('a1000000-0000-0000-0000-000000000002', '${voterId}', 'worker') ON CONFLICT DO NOTHING;
        INSERT INTO staff (id, venue_id, user_id, first_name, last_name, phone, emergency_contact_name, emergency_contact_phone)
        VALUES ('${voterId}', 'a1000000-0000-0000-0000-000000000002', '${voterId}', 'Cross', 'Venue', '0400000000', 'E2E Contact', '0400000001') ON CONFLICT (id) DO NOTHING;
        INSERT INTO staff_roster_groups (id, staff_id, roster_group_id)
        SELECT '${voterId}', '${voterId}', id FROM roster_groups WHERE venue_id = 'a1000000-0000-0000-0000-000000000002' AND is_active ORDER BY created_at LIMIT 1 ON CONFLICT (id) DO NOTHING;
        DELETE FROM user_feedback_items WHERE id IN ('${privateId}', '${archivedId}');
        INSERT INTO user_feedback_items (id, venue_id, submitted_by_user_id, title, content, support_note, user_agent)
        SELECT '${privateId}', 'a1000000-0000-0000-0000-000000000001', id, 'Private retained sentinel', 'Private retained content', 'Private operator sentinel', 'Private browser sentinel'
        FROM users WHERE email = 'e2e-worker@example.com';
        INSERT INTO user_feedback_items (id, venue_id, submitted_by_user_id, title, content, lifecycle, archived_at, archived_by_user_id)
        SELECT '${archivedId}', 'a1000000-0000-0000-0000-000000000001', id, 'Archived retained sentinel', 'Archived retained content', 'archived', NOW(), id
        FROM users WHERE email = 'e2e-super-admin@example.com';
    `);
    const founderContext = await browser.newContext({ viewport: page.viewportSize() ?? undefined });
    const voterContext = await browser.newContext({ viewport: page.viewportSize() ?? undefined });
    const founder = await founderContext.newPage();
    const voter = await voterContext.newPage();
    const frames: string[] = [];
    voter.on('websocket', socket => socket.on('framereceived', frame => frames.push(frame.payload.toString())));
    const screenshot = async (owner: Page, name: string) => {
        const path = testInfo.outputPath(`${name}.png`);
        await owner.screenshot({ path, fullPage: true });
        await testInfo.attach(name, { path, contentType: 'image/png' });
    };
    try {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Feedback', '#feedback-cards');
        await loginAs(voter, voterEmail, 'test-password-123');
        await gotoWhenReady(voter, '/Feedback', '#feedback-cards');
        await expect(page.locator('#feedback-cards')).toContainText('No public feedback yet');
        await screenshot(page, 'feedback-empty');
        await loginAsPrivilegedUserWithSeededPasskeySession(founder, 'e2e-super-admin@example.com', 'test-password-123');
        await gotoWhenReady(founder, '/Feedback', '#feedback-review');
        await page.getByRole('link', { name: 'Add feedback', exact: true }).click();
        await page.getByLabel('Title', { exact: true }).fill(title);
        await page.getByLabel('Description', { exact: true }).fill('Shared improvement for all venues.');
        await screenshot(page, 'feedback-submission-modal');
        await page.locator('button[type="submit"][form="feedback-form"]').click();
        await expect(page.locator('#dialog-overlay-mount')).toBeEmpty();
        const itemId = querySql(`SELECT id FROM user_feedback_items WHERE title = '${title}'`);
        expect(itemId).toMatch(/^[0-9a-f-]{36}$/);
        expect(querySql(`SELECT submitted_path IS NULL AND user_agent IS NULL AND submitted_role IS NULL AND viewport_width IS NULL AND viewport_height IS NULL AND device_pixel_ratio IS NULL AND device_class IS NULL AND display_mode IS NULL FROM user_feedback_items WHERE id = '${itemId}'`)).toBe('t');
        const management = founder.locator('#feedback-review article').filter({ has: founder.getByRole('heading', { name: title, exact: true }) });
        await expect(management).toBeVisible();
        await screenshot(founder, 'feedback-private-and-archived');
        const assertOrdinaryPrivacy = async (owner: Page) => {
            const html = await owner.content();
            for (const secret of [privateId, archivedId, 'Private retained sentinel', 'Archived retained sentinel', 'Private operator sentinel', 'Private browser sentinel', 'e2e-worker@example.com']) expect(html).not.toContain(secret);
            await expect(owner.locator('#feedback-review, #feedback-desktop-count, #feedback-mobile-count')).toHaveCount(0);
        };
        await assertOrdinaryPrivacy(voter);
        for (const endpoint of ['ShowFeedbackReview', 'ShowFeedbackDesktopCount', 'ShowFeedbackMobileCount', `EditFeedback?feedbackItemId=${itemId}`]) {
            const denied = await voter.request.get(`/${endpoint}`);
            expect(denied.status()).toBe(403);
            expect(await denied.text()).not.toContain(title);
        }
        // Private edit/archive/restore must not leak even a public invalidation.
        await management.getByRole('link', { name: 'Edit', exact: true }).click();
        await founder.getByLabel('Description', { exact: true }).fill('Editorially reviewed shared improvement.');
        await founder.getByRole('button', { name: 'Save', exact: true }).click();
        await expect(founder.locator('#dialog-overlay-mount')).toBeEmpty();
        await management.getByRole('button', { name: 'Confirm archive', exact: true }).click();
        await management.getByRole('button', { name: 'Restore', exact: true }).click();
        await management.getByRole('button', { name: 'Publish', exact: true }).click();
        await expect(voter.locator('#feedback-cards')).toContainText(title);
        const publicInvalidations = () => frames.map(raw => JSON.parse(raw)).filter(message => message.type === 'invalidate' && message.scope?.surface === 'feedback');
        await expect.poll(() => publicInvalidations().length, { timeout: E2E_TIMEOUT.assertion }).toBe(1);
        for (const raw of frames) for (const secret of [privateId, archivedId, 'Private operator sentinel', title]) expect(raw).not.toContain(secret);
        await screenshot(founder, 'feedback-all-three-sections');
        const authorVote = page.getByRole('button', { name: `Vote for ${title}`, exact: true });
        const otherVote = voter.getByRole('button', { name: `Vote for ${title}`, exact: true });
        await expect(authorVote).toHaveAttribute('aria-pressed', 'true');
        await expect(otherVote).toHaveAttribute('aria-pressed', 'false');
        await otherVote.click();
        await expect(otherVote).toHaveAttribute('aria-pressed', 'true');
        await expect(management).toContainText('2 votes');
        await screenshot(voter, 'feedback-voted-public');
        await otherVote.click();
        await expect(management).toContainText('1 votes');
        await management.getByRole('link', { name: 'Edit', exact: true }).click();
        await founder.getByLabel('Description', { exact: true }).fill('Public revision preserves votes.');
        await founder.getByRole('button', { name: 'Save', exact: true }).click();
        await expect(voter.locator('#feedback-cards')).toContainText('Public revision preserves votes.');
        await expect(authorVote).toHaveAttribute('aria-pressed', 'true');
        await management.locator('summary').filter({ hasText: /^Archive$/ }).click();
        await management.getByRole('button', { name: 'Confirm archive', exact: true }).click();
        await expect(voter.locator('#feedback-cards')).not.toContainText(title);
        expect(querySql(`SELECT count(*) FROM feedback_votes WHERE feedback_item_id = '${itemId}'`)).toBe('0');
        await screenshot(founder, 'feedback-archived');
        await management.getByRole('button', { name: 'Restore', exact: true }).click();
        await expect(management.getByRole('button', { name: 'Publish', exact: true })).toBeVisible();
        await assertOrdinaryPrivacy(voter);
        expect(await voter.content()).not.toContain(itemId);
        await management.getByRole('button', { name: 'Publish', exact: true }).click();
        await expect(authorVote).toHaveAttribute('aria-pressed', 'true');
        await expect(otherVote).toHaveAttribute('aria-pressed', 'false');
        await expect(voter.locator('#feedback-cards')).toContainText('1 votes');
        expect(querySql(`SELECT count(*) FROM feedback_votes WHERE feedback_item_id = '${itemId}'`)).toBe('1');
        expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    } finally {
        await founderContext.close();
        await voterContext.close();
        runSql(`BEGIN; SET LOCAL ihp_roster.allow_hard_delete = 'on'; DELETE FROM user_feedback_items WHERE title = '${title}' OR id IN ('${privateId}', '${archivedId}'); DELETE FROM audit_events WHERE actor_user_id = '${voterId}'; DELETE FROM staff_roster_groups WHERE staff_id = '${voterId}'; DELETE FROM staff WHERE id = '${voterId}'; DELETE FROM venue_memberships WHERE user_id = '${voterId}'; DELETE FROM users WHERE id = '${voterId}'; COMMIT;`);
    }
});
