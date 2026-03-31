import { expect, Page, test } from '@playwright/test';
import { gotoWhenReady, loginAs } from './test-helpers';

const managerCreds = {
    email: 'e2e-test@example.com',
    password: 'test-password-123',
};

const workerCreds = {
    email: 'e2e-worker@example.com',
    password: 'test-password-123',
};

async function loginManager(page) {
    await loginAs(page, managerCreds.email, managerCreds.password);
}

async function loginWorker(page) {
    await loginAs(page, workerCreds.email, workerCreds.password);
}

async function setFlatpickrDate(page: Page, selector: string, value: string) {
    await page.locator(selector).evaluate((input, nextValue) => {
        const flatpickr = (input as HTMLInputElement & {
            _flatpickr?: { setDate: (date: string, triggerChange?: boolean) => void };
        })._flatpickr;

        if (!flatpickr) {
            throw new Error(`No flatpickr instance on ${selector}`);
        }

        flatpickr.setDate(nextValue as string, true);
    }, value);
}

async function isoToday(page: Page) {
    return page.evaluate(() => {
        const now = new Date();
        const year = now.getUTCFullYear();
        const month = String(now.getUTCMonth() + 1).padStart(2, '0');
        const day = String(now.getUTCDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    });
}

async function isoCurrentWeekStart(page: Page) {
    return page.evaluate(() => {
        const now = new Date();
        const current = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
        const day = current.getUTCDay();
        const mondayOffset = day === 0 ? 6 : day - 1;
        current.setUTCDate(current.getUTCDate() - mondayOffset);
        return current.toISOString().slice(0, 10);
    });
}

async function createLeaveRequest(page: Page, note: string, startDate: string, endDate: string) {
    await page.getByRole('link', { name: 'New Request' }).click();
    await expect(page.locator('#leave-request-form')).toBeVisible();
    await setFlatpickrDate(page, '#startDate', startDate);
    await setFlatpickrDate(page, '#endDate', endDate);
    await page.fill('#notes', note);
    await page.getByRole('button', { name: 'Save' }).click();
    await expect(page.locator('#dialog-overlay-mount')).toBeEmpty();
    await expect(page.locator('#leave-requests-content')).toContainText(note);
}

async function denyApprovedLeaveRows(page: Page) {
    while (true) {
        const approvedRows = page.locator('#leave-requests-content tr').filter({ hasText: 'Alpha Crew' }).filter({ hasText: 'Approved' });
        const approvedCount = await approvedRows.count();

        if (approvedCount === 0) {
            return;
        }

        await approvedRows.first().getByRole('button', { name: 'Deny' }).click();
        await expect(approvedRows).toHaveCount(approvedCount - 1);
    }
}

async function createTimesheet(page: Page, startTime: string, endTime: string) {
    await page.getByRole('link', { name: 'Add Timesheet' }).first().click();
    await expect(page.locator('#timesheet-entry-create-form')).toBeVisible();
    await page.locator('input[name="startTime"]').evaluate((input, value) => {
        (input as HTMLInputElement).value = value as string;
    }, startTime);
    await page.locator('input[name="endTime"]').evaluate((input, value) => {
        (input as HTMLInputElement).value = value as string;
    }, endTime);
    await page.getByRole('button', { name: 'Save' }).click();
    await expect(page.locator('#dialog-overlay-mount')).toBeEmpty();
}

test.describe('Live fragment multi-view coverage', () => {
    test.setTimeout(120000);

    test('manager approval updates the worker leave page live', async ({ browser }) => {
        const managerContext = await browser.newContext();
        const workerContext = await browser.newContext();
        const managerPage = await managerContext.newPage();
        const workerPage = await workerContext.newPage();
        const note = `worker-live-leave-${Date.now()}`;

        await loginManager(managerPage);
        await loginWorker(workerPage);

        await gotoWhenReady(managerPage, '/LeaveRequests', '#leave-requests-content');
        await gotoWhenReady(workerPage, '/LeaveRequests', '#leave-requests-content');

        const startDate = await isoCurrentWeekStart(workerPage);
        const endDate = await workerPage.evaluate((start) => {
            const next = new Date(`${start}T00:00:00Z`);
            next.setUTCDate(next.getUTCDate() + 1);
            return next.toISOString().slice(0, 10);
        }, startDate);

        await createLeaveRequest(workerPage, note, startDate, endDate);

        const managerRow = managerPage.locator('#leave-requests-content tr').filter({ hasText: note });
        const workerRow = workerPage.locator('#leave-requests-content tr').filter({ hasText: note });

        await expect(managerRow).toHaveCount(1);
        await expect(managerRow).toContainText('Pending');
        await expect(workerRow).toHaveCount(1);
        await expect(workerRow).toContainText('Pending');
        await expect(workerRow.getByRole('button', { name: 'Delete' })).toHaveCount(1);

        await managerRow.getByRole('button', { name: 'Approve' }).click();

        await expect(managerRow).toContainText('Approved');
        await expect(workerRow).toContainText('Approved');
        await expect(workerRow.getByRole('button', { name: 'Delete' })).toHaveCount(0);

        await managerContext.close();
        await workerContext.close();
    });

    test('leave approval updates an open roster viewer with the new conflict state', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const workerContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const workerPage = await workerContext.newPage();
        const viewerPage = await viewerContext.newPage();
        const note = `roster-live-leave-${Date.now()}`;

        await loginManager(actorPage);
        await gotoWhenReady(actorPage, '/LeaveRequests', '#leave-requests-content');
        await denyApprovedLeaveRows(actorPage);

        await loginWorker(workerPage);
        await gotoWhenReady(workerPage, '/LeaveRequests', '#leave-requests-content');
        const startDate = await isoCurrentWeekStart(workerPage);
        const endDate = await workerPage.evaluate((start) => {
            const next = new Date(`${start}T00:00:00Z`);
            next.setUTCDate(next.getUTCDate() + 1);
            return next.toISOString().slice(0, 10);
        }, startDate);
        await createLeaveRequest(workerPage, note, startDate, endDate);

        await loginManager(viewerPage);
        await gotoWhenReady(viewerPage, '/RosterWeeks', '#roster-content');
        await expect(viewerPage.locator('.slot-staff-cell.conflict-critical')).toHaveCount(0);

        const leaveRow = actorPage.locator('#leave-requests-content tr').filter({ hasText: note });

        await expect(leaveRow).toContainText('Pending');
        await expect(viewerPage.locator('#roster-content')).toBeVisible();

        await leaveRow.getByRole('button', { name: 'Approve' }).click();

        await expect(leaveRow).toContainText('Approved');
        const viewerConflictCell = viewerPage.locator('.slot-staff-cell.conflict-critical').first();
        await expect
            .poll(async () => viewerPage.locator('.slot-staff-cell.conflict-critical').count(), { timeout: 15000 })
            .toBe(1);
        await expect(viewerConflictCell.locator('.badge')).toHaveAttribute('title', /leave/i);

        await actorContext.close();
        await workerContext.close();
        await viewerContext.close();
    });

    test('manager approval updates the worker timesheet page live', async ({ browser }) => {
        const managerContext = await browser.newContext();
        const workerContext = await browser.newContext();
        const managerPage = await managerContext.newPage();
        const workerPage = await workerContext.newPage();
        const renderedRange = '11:15 AM - 3:15 PM';

        await loginManager(managerPage);
        await loginWorker(workerPage);

        await gotoWhenReady(managerPage, '/Timesheets', '#timesheet-week-shell');
        await gotoWhenReady(workerPage, '/Timesheets', '#timesheet-week-shell');

        await createTimesheet(workerPage, '11:15', '15:15');

        const managerEntry = managerPage.locator('#timesheet-day-section-0 .border.rounded').filter({ hasText: renderedRange });
        const workerEntry = workerPage.locator('#timesheet-day-section-0 .border.rounded').filter({ hasText: renderedRange });

        await expect(managerEntry).toHaveCount(1);
        await expect(managerEntry).toContainText('Pending');
        await expect(workerEntry).toHaveCount(1);
        await expect(workerEntry).toContainText('Pending');

        await managerEntry.getByRole('button', { name: 'Approve' }).click();

        await expect(managerEntry).toContainText('Approved');
        await expect(workerEntry).toContainText('Approved');

        await managerContext.close();
        await workerContext.close();
    });
});
