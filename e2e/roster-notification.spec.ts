import { randomUUID } from 'node:crypto';
import { test, expect } from '@playwright/test';
import {
    defaultE2ERosterGroupId,
    E2E_TIMEOUT,
    openRoster,
    mailhogMessageSubject,
    mailhogMessageText,
    openRosterSettings,
    querySql,
    runSql,
    uniqueE2EValue,
    waitForMailhogMessages,
} from './test-helpers';

test.describe('Roster notification workflow', () => {
    test('opens confirmation in place for managers and stays hidden from workers', async ({ browser, page }, testInfo) => {
        test.skip(testInfo.project.name !== 'desktop-chromium', 'Role-specific notification workflow is covered once on desktop.');
        await openRoster(page);
        const weekOffset = Number.parseInt(new URL(page.url()).searchParams.get('weekOffset') ?? '0', 10);
        runSql(`UPDATE roster_weeks SET is_live = TRUE WHERE roster_group_id = '${defaultE2ERosterGroupId}' AND week_offset = ${weekOffset};`);
        try {
            await page.reload();
            await expect(page.locator('#roster-week-shell')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
            await openRosterSettings(page);
            const emailRoster = page.locator('#roster-email-button');
            await expect(emailRoster).toBeVisible();
            await expect(emailRoster).toBeEnabled();
            const originalUrl = page.url();
            await page.evaluate(() => { (window as Window & { __notificationMarker?: string }).__notificationMarker = 'preserved'; });
            await emailRoster.click();
            const dialog = page.getByRole('dialog', { name: 'Email roster' });
            await expect(dialog).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
            await expect(dialog).toContainText('Recipients');
            expect(page.url()).toBe(originalUrl);
            expect(await page.evaluate(() => (window as Window & { __notificationMarker?: string }).__notificationMarker)).toBe('preserved');

            const workerContext = await browser.newContext();
            const workerPage = await workerContext.newPage();
            try {
                await openRoster(workerPage, {
                    email: 'e2e-worker@example.com',
                    weekOffset,
                    ensureDraft: false,
                    ensureEditable: false,
                });
                await expect(workerPage.locator('#roster-email-button')).toHaveCount(0);
            } finally {
                await workerContext.close();
            }
        } finally {
            runSql(`UPDATE roster_weeks SET is_live = FALSE WHERE roster_group_id = '${defaultE2ERosterGroupId}' AND week_offset = ${weekOffset};`);
        }
    });

    test('delivers a queued snapshot after unpublish and allows a terminal repeat send', async ({ page, request }, testInfo) => {
        test.skip(testInfo.project.name !== 'desktop-chromium', 'Mail delivery acceptance is covered once on desktop.');
        testInfo.setTimeout(E2E_TIMEOUT.slowTest);
        const recipientEmail = `${uniqueE2EValue('e2e-roster-notification')}-retry-${testInfo.retry}@example.com`;
        const rosterGroupId = randomUUID();
        const rosterWeekId = randomUUID();
        const rosterGroupName = uniqueE2EValue('e2e-notification-acceptance');
        runSql(`
            DELETE FROM staff_roster_groups
            WHERE staff_id IN (
                SELECT staff.id FROM staff
                JOIN users ON users.id = staff.user_id
                WHERE users.email LIKE 'e2e-roster-notification-%@example.com'
            );
            DELETE FROM staff
            WHERE user_id IN (SELECT id FROM users WHERE email LIKE 'e2e-roster-notification-%@example.com');
            DELETE FROM venue_memberships
            WHERE user_id IN (SELECT id FROM users WHERE email LIKE 'e2e-roster-notification-%@example.com');
            DELETE FROM users WHERE email LIKE 'e2e-roster-notification-%@example.com';

            INSERT INTO roster_groups (id, venue_id, name, sort_order, is_active, is_default)
            VALUES ('${rosterGroupId}', 'a1000000-0000-0000-0000-000000000001', '${rosterGroupName}', 99, TRUE, FALSE);
            INSERT INTO roster_weeks (id, venue_id, roster_group_id, week_offset, is_live)
            VALUES ('${rosterWeekId}', 'a1000000-0000-0000-0000-000000000001', '${rosterGroupId}', 0, TRUE);
            INSERT INTO roster_days (roster_week_id, day_offset, is_closed, row_count)
            SELECT '${rosterWeekId}', day_offset, FALSE, 2 FROM generate_series(0, 6) AS day_offset;
            INSERT INTO roster_week_slot_definitions (roster_week_id, name, sort_order)
            VALUES ('${rosterWeekId}', 'Acceptance lane', 0);
            INSERT INTO staff_roster_groups (staff_id, roster_group_id)
            SELECT staff_id, '${rosterGroupId}'
            FROM staff_roster_groups
            WHERE roster_group_id = '${defaultE2ERosterGroupId}' AND deleted_at IS NULL;

            WITH new_user AS (
                INSERT INTO users (email, password_hash, is_profile_completed, email_verified_at)
                SELECT '${recipientEmail}', password_hash, TRUE, NOW()
                FROM users
                WHERE email = 'e2e-worker@example.com'
                RETURNING id
            ), new_membership AS (
                INSERT INTO venue_memberships (venue_id, user_id, venue_role)
                SELECT 'a1000000-0000-0000-0000-000000000001', id, 'worker'
                FROM new_user
            ), new_staff AS (
                INSERT INTO staff (
                    venue_id, user_id, first_name, last_name, phone,
                    emergency_contact_name, emergency_contact_phone
                )
                SELECT
                    'a1000000-0000-0000-0000-000000000001', id,
                    'Notification', 'Acceptance', '0400000099',
                    'Acceptance Contact', '0400000199'
                FROM new_user
                RETURNING id
            )
            INSERT INTO staff_roster_groups (staff_id, roster_group_id)
            SELECT id, '${rosterGroupId}' FROM new_staff;
        `);

        await openRoster(page, {
            rosterGroupId,
            ensureDraft: false,
            ensureEditable: false,
        });
        const weekOffset = Number.parseInt(new URL(page.url()).searchParams.get('weekOffset') ?? '0', 10);
        try {
            await page.reload();
            await expect(page.locator('#roster-week-shell')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
            await openRosterSettings(page);
            await page.locator('#roster-email-button').click();
            const firstDialog = page.getByRole('dialog', { name: 'Email roster' });
            await expect(firstDialog).toContainText('4 recipients');
            await expect(firstDialog).toContainText('1 skipped');
            await firstDialog.getByRole('button', { name: 'Email roster', exact: true }).click();
            await expect(page.locator('body')).toContainText('Roster email queued for 4 recipients. 1 skipped.');

            runSql(`
                UPDATE roster_weeks
                SET is_live = FALSE
                WHERE id = '${rosterWeekId}';
            `);
            const firstMessages = await waitForMailhogMessages(request, recipientEmail, 1, E2E_TIMEOUT.mailhog);
            expect(mailhogMessageSubject(firstMessages[0])).toContain(`Your ${rosterGroupName} roster`);
            expect(mailhogMessageText(firstMessages[0])).toContain('You have no assigned shifts in this roster.');

            await expect.poll(() => Number.parseInt(querySql(`
                SELECT COUNT(*)
                FROM app_jobs
                WHERE related_id IN (
                    SELECT id FROM roster_notification_runs
                    WHERE roster_group_id = '${rosterGroupId}' AND week_offset = ${weekOffset}
                )
                  AND status IN ('job_status_not_started', 'job_status_running', 'job_status_retry');
            `), 10), { timeout: E2E_TIMEOUT.mailhog }).toBe(0);

            runSql(`
                UPDATE roster_weeks
                SET is_live = TRUE
                WHERE id = '${rosterWeekId}';
                UPDATE app_jobs
                SET status = 'job_status_retry', run_at = NOW() + INTERVAL '1 hour'
                WHERE payload ->> 'recipientEmail' = '${recipientEmail}';
            `);
            await page.reload();
            await openRosterSettings(page);
            await expect(page.locator('#roster-email-button')).toBeDisabled();
            await expect(page.locator('#roster-email-button')).toHaveAttribute('title', 'Roster email delivery is in progress');

            runSql(`
                UPDATE app_jobs
                SET status = CASE
                        WHEN payload ->> 'recipientEmail' = '${recipientEmail}' THEN 'job_status_failed'::job_status
                        ELSE 'job_status_succeeded'::job_status
                    END,
                    run_at = NOW()
                WHERE related_id = (
                    SELECT id FROM roster_notification_runs
                    WHERE roster_group_id = '${rosterGroupId}' AND week_offset = ${weekOffset}
                    ORDER BY created_at DESC LIMIT 1
                );
            `);
            await page.reload();
            await openRosterSettings(page);
            await expect(page.locator('#roster-email-button')).toBeEnabled();
            await page.locator('#roster-email-button').click();
            const repeatDialog = page.getByRole('dialog', { name: 'Email roster' });
            await expect(repeatDialog.locator('#roster-notification-latest-run-heading').locator('..')).toContainText('Failed1');
            await repeatDialog.getByRole('button', { name: 'Email roster', exact: true }).click();
            await expect(page.locator('body')).toContainText('Roster email queued for 4 recipients. 1 skipped.');
            await waitForMailhogMessages(request, recipientEmail, 2, E2E_TIMEOUT.mailhog);
        } finally {
            runSql(`
                UPDATE roster_weeks
                SET is_live = FALSE
                WHERE id = '${rosterWeekId}';
                UPDATE roster_groups
                SET is_active = FALSE
                WHERE id = '${rosterGroupId}';
            `);
        }
    });
});
