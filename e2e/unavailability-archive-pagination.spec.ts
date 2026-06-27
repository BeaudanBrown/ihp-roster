import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT, gotoWhenReady, loginAs, runSql } from './test-helpers';

test.describe('unavailability archive pagination', () => {
    test('updates archive rows without closing the archive accordion or reloading the page', async ({ page }) => {
        runSql(`
            INSERT INTO leave_requests (id, venue_id, staff_id, start_date, end_date, status, notes, deleted_at, deleted_by_user_id, delete_reason)
            SELECT
                ('b2000000-0000-0000-0000-' || lpad(series_index::text, 12, '0'))::uuid,
                'a1000000-0000-0000-0000-000000000001'::uuid,
                'a0000000-0000-0000-0000-000000000101'::uuid,
                CURRENT_DATE - (series_index + 1),
                CURRENT_DATE - series_index,
                'approved',
                'e2e-archive-pagination-' || series_index::text,
                NULL,
                NULL,
                NULL
            FROM generate_series(1, 12) AS series_index
            ON CONFLICT (id) DO UPDATE SET
                venue_id = EXCLUDED.venue_id,
                staff_id = EXCLUDED.staff_id,
                start_date = EXCLUDED.start_date,
                end_date = EXCLUDED.end_date,
                status = EXCLUDED.status,
                notes = EXCLUDED.notes,
                deleted_at = NULL,
                deleted_by_user_id = NULL,
                delete_reason = NULL,
                updated_at = NOW();
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
        if ((await archivePageTwo.count()) === 0) {
            await expect(page.locator('#leave-archive-heading .accordion-button')).toContainText('Archive');
            return;
        }
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
