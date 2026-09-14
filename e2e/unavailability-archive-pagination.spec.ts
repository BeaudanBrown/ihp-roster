import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady } from './support/runtime';
import { loginAs } from './support/session';
import { runSql } from './support/database';

test.describe('unavailability archive pagination', () => {
    test('updates archive rows without leaving the Archive tab or reloading the page', async ({ page }) => {
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
        await gotoWhenReady(page, '/LeaveRequests', '#leave-requests-shell');

        const archiveTab = page.getByRole('tab', { name: 'Archive', exact: true });
        await archiveTab.click();
        await expect(archiveTab).toHaveAttribute('aria-selected', 'true', { timeout: E2E_TIMEOUT.action });
        await expect(page.getByRole('tab', { name: 'Pending', exact: true })).toHaveAttribute('aria-selected', 'false', { timeout: E2E_TIMEOUT.action });

        await page.evaluate(() => {
            (window as Window & { __archivePagerNoReload?: boolean }).__archivePagerNoReload = true;
        });

        const archivePageTwo = page.getByRole('link', { name: 'Archive page 2' }).first();
        await expect(archivePageTwo).toBeVisible({ timeout: E2E_TIMEOUT.assertion });

        await Promise.all([
            page.waitForResponse(
                (response) => {
                    const url = new URL(response.url());
                    return url.pathname === '/ShowleaveRequestsContentLiveFragment'
                        && url.searchParams.get('archivePage') === '2'
                        && url.searchParams.get('swapOob') === 'true'
                        && response.status() === 200;
                },
                { timeout: E2E_TIMEOUT.navigation },
            ),
            archivePageTwo.click(),
        ]);

        await expect.poll(
            async () => archiveTab.getAttribute('aria-selected'),
            { timeout: E2E_TIMEOUT.assertion },
        ).toBe('true');
        await expect(page.getByRole('tab', { name: 'Pending', exact: true })).toHaveAttribute('aria-selected', 'false', { timeout: E2E_TIMEOUT.assertion });
        await expect(page.getByRole('tabpanel', { name: 'Archive', exact: true })).toBeVisible();
        await expect(page.locator('#leave-archive-page-content')).toContainText('e2e-archive-pagination-12', { timeout: E2E_TIMEOUT.assertion });
        await expect.poll(
            async () => page.evaluate(() => (window as Window & { __archivePagerNoReload?: boolean }).__archivePagerNoReload === true),
            { timeout: E2E_TIMEOUT.assertion },
        ).toBe(true);
    });
});
