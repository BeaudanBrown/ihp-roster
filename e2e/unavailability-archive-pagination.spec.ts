import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT, gotoWhenReady, loginAs, runSql } from './test-helpers';

test.describe('unavailability archive pagination', () => {
    test('updates archive rows without closing the archive accordion or reloading the page', async ({ page }) => {
        runSql(`
            WITH manager_user AS (
                SELECT id FROM users WHERE email = 'e2e-test@example.com' LIMIT 1
            ), manager_venue AS (
                SELECT venue_id FROM venue_memberships
                WHERE user_id = (SELECT id FROM manager_user)
                AND is_active = TRUE
                LIMIT 1
            ), archive_staff AS (
                SELECT id FROM staff
                WHERE venue_id = (SELECT venue_id FROM manager_venue)
                ORDER BY created_at ASC
                LIMIT 1
            )
            DELETE FROM leave_requests
            WHERE notes LIKE 'e2e-archive-pagination-%'
            AND venue_id = (SELECT venue_id FROM manager_venue);

            WITH manager_user AS (
                SELECT id FROM users WHERE email = 'e2e-test@example.com' LIMIT 1
            ), manager_venue AS (
                SELECT venue_id FROM venue_memberships
                WHERE user_id = (SELECT id FROM manager_user)
                AND is_active = TRUE
                LIMIT 1
            ), archive_staff AS (
                SELECT id FROM staff
                WHERE venue_id = (SELECT venue_id FROM manager_venue)
                ORDER BY created_at ASC
                LIMIT 1
            )
            INSERT INTO leave_requests (venue_id, staff_id, start_date, end_date, status, notes)
            SELECT
                (SELECT venue_id FROM manager_venue),
                (SELECT id FROM archive_staff),
                CURRENT_DATE - (series_index + 1),
                CURRENT_DATE - series_index,
                'approved',
                'e2e-archive-pagination-' || series_index::text
            FROM generate_series(1, 12) AS series_index;
        `);

        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/LeaveRequests', '#leave-requests-content');

        const archiveToggle = page.locator('#leave-archive-heading .accordion-button');
        if ((await archiveToggle.getAttribute('aria-expanded')) !== 'true') {
            await archiveToggle.click();
        }
        await expect(archiveToggle).toHaveAttribute('aria-expanded', 'true', { timeout: E2E_TIMEOUT.action });
        await expect(page.locator('#leave-pending-heading .accordion-button')).toHaveAttribute('aria-expanded', 'false', { timeout: E2E_TIMEOUT.action });

        await page.evaluate(() => {
            (window as Window & { __archivePagerNoReload?: boolean }).__archivePagerNoReload = true;
        });

        const archivePageTwo = page.getByRole('link', { name: 'Archive page 2' }).first();
        await expect(archivePageTwo).toBeVisible({ timeout: E2E_TIMEOUT.assertion });

        await Promise.all([
            page.waitForResponse(
                (response) => {
                    const url = new URL(response.url());
                    return url.pathname === '/ShowLeaveRequestsContentFragment'
                        && url.searchParams.get('archivePage') === '2'
                        && url.searchParams.get('swapOob') === 'true'
                        && response.status() === 200;
                },
                { timeout: E2E_TIMEOUT.navigation },
            ),
            archivePageTwo.click(),
        ]);

        await expect.poll(
            async () => page.locator('#leave-archive-heading .accordion-button').getAttribute('aria-expanded'),
            { timeout: E2E_TIMEOUT.assertion },
        ).toBe('true');
        await expect(page.locator('#leave-pending-heading .accordion-button')).toHaveAttribute('aria-expanded', 'false', { timeout: E2E_TIMEOUT.assertion });
        await expect(page.locator('#leave-archive-page-content')).toContainText('e2e-archive-pagination-11', { timeout: E2E_TIMEOUT.assertion });
        await expect.poll(
            async () => page.evaluate(() => (window as Window & { __archivePagerNoReload?: boolean }).__archivePagerNoReload === true),
            { timeout: E2E_TIMEOUT.assertion },
        ).toBe(true);
    });
});
