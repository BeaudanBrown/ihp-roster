import { test, expect } from '@playwright/test';
import {
    expectContainerToManageHorizontalOverflow,
    expectDialogToFitViewport,
    expectNoHorizontalViewportOverflow,
    gotoWhenReady,
    loginAs,
    openAuthenticatedNavIfCollapsed,
} from './test-helpers';

test.describe('Mobile experience smoke', () => {
    test('authenticated navigation remains usable when the header collapses', async ({ page }) => {
        await loginAs(page, 'e2e-admin@example.com', 'test-password-123');

        const navToggle = page.locator('.navbar-toggler');
        if (await navToggle.isVisible()) {
            await expect(navToggle).toBeVisible();
        }

        await openAuthenticatedNavIfCollapsed(page);
        await expect(page.getByRole('link', { name: 'schedule', exact: true })).toBeVisible();
        await expect(page.getByRole('link', { name: 'timesheets' })).toBeVisible();
        await expect(page.getByRole('link', { name: 'leave' })).toBeVisible();
        await expect(page.getByRole('link', { name: 'admin' })).toBeVisible();

        await page.getByRole('link', { name: 'leave' }).click();
        await expect(page).toHaveURL(/LeaveRequests/, { timeout: 60000 });
        await expect(page.locator('#leave-requests-content')).toBeVisible();

        await openAuthenticatedNavIfCollapsed(page);
        await page.getByRole('link', { name: 'timesheets' }).click();
        await expect(page).toHaveURL(/(Timesheets|ShowTimesheetWeek)/, { timeout: 60000 });
        await expect(page.locator('#timesheet-week-shell')).toBeVisible();
    });

    test('roster creator remains usable on a narrow viewport without leaking page-level overflow', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await expect(page.locator('table.roster-grid')).toBeVisible();

        const firstDaySection = page.locator('tbody[data-roster-day-section]').first();
        const dayRows = firstDaySection.locator('tr[data-roster-row]').filter({ has: page.locator('select[name="staffId"]') });
        const initialRowCount = await dayRows.count();

        await expectContainerToManageHorizontalOverflow(page, '.table-responsive');
        await expectNoHorizontalViewportOverflow(page);

        const addButton = page.locator('[data-roster-day-add="true"]').first();
        await addButton.evaluate((button: HTMLButtonElement) => button.click());
        await expect(dayRows).toHaveCount(initialRowCount + 1);
        await expectNoHorizontalViewportOverflow(page);
    });

    test('leave requests open a phone-sized workflow dialog that fits the viewport', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/LeaveRequests', '#leave-requests-content');

        await expect(page.locator('#leave-requests-content')).toBeVisible();
        await expectNoHorizontalViewportOverflow(page);

        await page.getByRole('link', { name: 'New Request' }).click();
        await expect(page.locator('#leave-request-form')).toBeVisible();
        await expectDialogToFitViewport(page, '#dialog-overlay-mount .modal-dialog, #dialog-overlay-mount [role="dialog"]');
    });

    test('timesheet creation dialog remains usable on a phone-sized viewport', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');

        await expect(page.locator('#timesheet-day-section-0')).toBeVisible();
        await expectNoHorizontalViewportOverflow(page);

        const addBar = page.locator('[data-timesheet-day-add="true"]').first();
        await expect(addBar).toBeVisible();
        await addBar.click();
        await expect(page.locator('#timesheet-entry-create-form')).toBeVisible();
        await expectDialogToFitViewport(page, '#dialog-overlay-mount .modal-dialog, #dialog-overlay-mount [role="dialog"]');
    });

    test('timesheet entries use stacked mobile actions and hide edit on approved entries', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');

        const approvedEntry = page.locator('[data-timesheet-entry-approved="true"]').first();
        const pendingEntry = page.locator('[data-timesheet-entry-approved="false"]').first();

        await expect(approvedEntry).toBeVisible();
        await expect(pendingEntry).toBeVisible();
        await expect(approvedEntry.locator('.timesheet-entry-actions .btn:has-text("Edit")')).toHaveCount(0);
        await expect(pendingEntry.locator('.timesheet-entry-actions .btn:has-text("Edit")')).toHaveCount(1);
        await expect(page.locator('.timesheet-shape-bar').first()).toBeVisible();
    });
});
