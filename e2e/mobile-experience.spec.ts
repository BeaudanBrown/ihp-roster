import { test, expect } from '@playwright/test';
import {
    expectContainerToManageHorizontalOverflow,
    expectDialogToFitViewport,
    expectNoHorizontalViewportOverflow,
    gotoWhenReady,
    loginAs,
    openNewLeaveRequestDialog,
    openAuthenticatedNavIfCollapsed,
} from './test-helpers';

test.describe('Mobile experience smoke', () => {
    test('manager navigation remains usable when the header collapses', async ({ page }) => {
        await loginAs(page, 'e2e-admin@example.com', 'test-password-123');

        const navToggle = page.locator('.navbar-toggler');
        if (await navToggle.isVisible()) {
            await expect(navToggle).toBeVisible();
        }

        const openedDrawer = await openAuthenticatedNavIfCollapsed(page);
        if (openedDrawer) {
            const mobileNav = page.locator('#app-mobile-nav');
            await expect(mobileNav).toBeVisible();
            await expect(mobileNav.getByRole('link', { name: 'Roster', exact: true })).toHaveAttribute('aria-current', 'page');
            await expect(mobileNav.getByRole('link', { name: 'Timesheets' })).toBeVisible();
            await expect(mobileNav.getByRole('link', { name: 'Leave' })).toBeVisible();
            await expect(mobileNav.getByRole('link', { name: 'Admin' })).toBeVisible();
            await expect(mobileNav.getByRole('button', { name: 'Logout' })).toBeVisible();

            const drawerMetrics = await mobileNav.evaluate((drawer) => {
                if (!(drawer instanceof HTMLElement)) {
                    throw new Error('Expected mobile nav drawer to be an HTMLElement');
                }

                const firstLink = drawer.querySelector('.app-mobile-nav-link');
                if (!(firstLink instanceof HTMLElement)) {
                    throw new Error('Expected mobile nav link to be an HTMLElement');
                }

                const drawerRect = drawer.getBoundingClientRect();
                const linkRect = firstLink.getBoundingClientRect();
                return {
                    drawerLeft: Math.round(drawerRect.left),
                    drawerRight: Math.round(drawerRect.right),
                    viewportWidth: window.innerWidth,
                    linkHeight: Math.round(linkRect.height),
                    linkDisplay: getComputedStyle(firstLink).display,
                };
            });

            expect(drawerMetrics.drawerLeft).toBeGreaterThanOrEqual(0);
            expect(drawerMetrics.drawerRight).toBeLessThanOrEqual(drawerMetrics.viewportWidth);
            expect(drawerMetrics.linkHeight).toBeGreaterThanOrEqual(44);
            expect(drawerMetrics.linkDisplay).toBe('flex');
            await mobileNav.getByRole('button', { name: 'Close navigation menu' }).click();
            await expect(mobileNav).toBeHidden();

            await openAuthenticatedNavIfCollapsed(page);
            await page.locator('#app-mobile-nav').getByRole('link', { name: 'Leave' }).click();
        } else {
            await expect(page.getByRole('link', { name: 'roster', exact: true })).toHaveAttribute('aria-current', 'page');
            await expect(page.getByRole('link', { name: 'timesheets' })).toBeVisible();
            await expect(page.getByRole('link', { name: 'leave' })).toBeVisible();
            await expect(page.getByRole('link', { name: 'admin' })).toBeVisible();
            await page.getByRole('link', { name: 'leave' }).click();
        }
        await expect(page).toHaveURL(/LeaveRequests/, { timeout: 60000 });
        await expect(page.locator('#leave-requests-content')).toBeVisible();

        const reopenedDrawer = await openAuthenticatedNavIfCollapsed(page);
        if (reopenedDrawer) {
            await page.locator('#app-mobile-nav').getByRole('link', { name: 'Timesheets' }).click();
        } else {
            await page.getByRole('link', { name: 'timesheets' }).click();
        }
        await expect(page).toHaveURL(/(Timesheets|ShowTimesheetWeek)/, { timeout: 60000 });
        await expect(page.locator('#timesheet-week-shell')).toBeVisible();
    });

    test('worker mobile navigation uses profile for leave access and hides the leave header link', async ({ page }) => {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');

        const openedDrawer = await openAuthenticatedNavIfCollapsed(page);
        if (openedDrawer) {
            const mobileNav = page.locator('#app-mobile-nav');
            await expect(mobileNav.getByRole('link', { name: 'Roster', exact: true })).toBeVisible();
            await expect(mobileNav.getByRole('link', { name: 'Profile' })).toBeVisible();
            await expect(mobileNav.getByRole('link', { name: 'Timesheets' })).toBeVisible();
            await expect(mobileNav.getByRole('link', { name: 'Leave' })).toHaveCount(0);
            await expect(mobileNav.getByRole('link', { name: 'Admin' })).toHaveCount(0);

            await mobileNav.getByRole('link', { name: 'Profile' }).click();
        } else {
            await expect(page.getByRole('link', { name: 'roster', exact: true })).toBeVisible();
            await expect(page.getByRole('link', { name: 'profile' })).toBeVisible();
            await expect(page.getByRole('link', { name: 'timesheets' })).toBeVisible();
            await expect(page.getByRole('link', { name: 'leave' })).toHaveCount(0);
            await expect(page.getByRole('link', { name: 'admin' })).toHaveCount(0);

            await page.getByRole('link', { name: 'profile' }).click();
        }
        await expect(page).toHaveURL(/EditProfile/, { timeout: 60000 });
        await expect(page.locator('#profile-content-fragment')).toBeVisible();

        const leaveSectionToggle = page.getByRole('button', { name: 'Leave Requests' });
        if ((await leaveSectionToggle.getAttribute('aria-expanded')) !== 'true') {
            await leaveSectionToggle.click();
        }

        await expect(page.locator('#profile-leave-request-form-fragment')).toBeVisible();
        await expect(page.locator('#profile-leave-requests-list-fragment')).toBeVisible();
        await expectNoHorizontalViewportOverflow(page);
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

        await openNewLeaveRequestDialog(page);
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

    test('timesheet entries use uniform mobile actions for approved and pending entries', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Timesheets?showApproved=true', '#timesheet-week-shell');

        const approvedEntry = page.locator('[data-timesheet-entry-approved="true"]').first();
        const pendingEntry = page.locator('[data-timesheet-entry-approved="false"]').first();

        await expect(approvedEntry).toBeVisible();
        await expect(pendingEntry).toBeVisible();
        await expect(approvedEntry.getByRole('button', { name: 'Approved' })).toBeVisible();
        await expect(pendingEntry.getByRole('button', { name: 'Approve' })).toBeVisible();
        await expect(approvedEntry.locator('.timesheet-entry-actions .btn:has-text("Edit")')).toHaveCount(1);
        await expect(pendingEntry.locator('.timesheet-entry-actions .btn:has-text("Edit")')).toHaveCount(1);
        await expect(page.locator('.timesheet-shape-bar').first()).toBeVisible();
    });
});
