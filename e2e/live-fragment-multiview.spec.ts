import { expect, Page, test } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { addRowToFirstRosterDay, editableRosterRows, gotoWhenReady, loginAs, openProfileLeaveSection, runSql, setFlatpickrDate } from './test-helpers';

const e2eRosterPath = '/ShowRosterWeek?weekOffset=0&rosterGroupId=a1000000-0000-0000-0000-000000000211';

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

async function loginAndOpenRoster(page) {
    await loginManager(page);
    await gotoWhenReady(page, e2eRosterPath, 'table.roster-grid');
    await expect(page.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
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

async function createProfileLeaveRequest(page: Page, note: string, startDate: string, endDate: string) {
    await openProfileLeaveSection(page);
    await setFlatpickrDate(page, '#startDate', startDate);
    await setFlatpickrDate(page, '#endDate', endDate);
    await page.fill('#notes', note);
    await page.getByRole('button', { name: 'Add unavailable time' }).click();
    await expect(page.locator('#profile-leave-request-form-fragment')).toBeVisible();
    await expect(page.locator('#profile-leave-requests-list-fragment')).toContainText(note);
}

async function createTimesheet(page: Page, startTime: string, endTime: string) {
    await page.locator('[data-timesheet-day-add="true"]').first().click();
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

async function ensureEditableRosterRow(page: Page, rowIndex: number) {
    for (let attempts = 0; attempts <= rowIndex; attempts += 1) {
        const rows = editableRosterRows(page);
        if (await rows.count() > rowIndex) {
            return rows.nth(rowIndex);
        }

        await addRowToFirstRosterDay(page);
        await expect(rows).toHaveCount(attempts + 2);
    }

    throw new Error(`Could not provision editable roster row ${rowIndex}`);
}

test.describe('Live fragment multi-view coverage', () => {
    test.setTimeout(E2E_TIMEOUT.slowTest);

    test('worker profile leave submit updates an open manager leave page live', async ({ browser }) => {
        const managerContext = await browser.newContext();
        const workerContext = await browser.newContext();
        const managerPage = await managerContext.newPage();
        const workerPage = await workerContext.newPage();
        const note = `worker-live-leave-${Date.now()}`;

        await loginManager(managerPage);
        await loginWorker(workerPage);

        await gotoWhenReady(managerPage, '/LeaveRequests', '#leave-requests-content');

        const startDate = await isoCurrentWeekStart(workerPage);
        const endDate = await workerPage.evaluate((start) => {
            const next = new Date(`${start}T00:00:00Z`);
            next.setUTCDate(next.getUTCDate() + 1);
            return next.toISOString().slice(0, 10);
        }, startDate);

        const managerContent = managerPage.locator('#leave-requests-content');
        await expect(managerContent).not.toContainText(note);

        await createProfileLeaveRequest(workerPage, note, startDate, endDate);

        const managerRow = managerPage.locator('#leave-requests-content article').filter({ hasText: note });
        await expect(managerRow).toHaveCount(1);
        await expect(managerRow).toContainText('Pending');
        await expect(managerContent).toContainText(note);

        await managerContext.close();
        await workerContext.close();
    });

    test('leave approval updates an open roster viewer with the new conflict state', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const requesterContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const requesterPage = await requesterContext.newPage();
        const viewerPage = await viewerContext.newPage();
        const note = 'Alpha leave request';
        const targetStaffId = 'a0000000-0000-0000-0000-000000000101';

        await loginManager(actorPage);
        await gotoWhenReady(actorPage, '/LeaveRequests', '#leave-requests-content');

        const startDate = await isoCurrentWeekStart(actorPage);
        const endDate = await actorPage.evaluate((start) => {
            const next = new Date(`${start}T00:00:00Z`);
            next.setUTCDate(next.getUTCDate() + 1);
            return next.toISOString().slice(0, 10);
        }, startDate);
        runSql(`
            UPDATE leave_requests
            SET
                start_date = '${startDate}',
                end_date = '${endDate}',
                staff_id = '${targetStaffId}',
                status = 'pending',
                deleted_at = NULL,
                updated_at = NOW()
            WHERE venue_id = 'a1000000-0000-0000-0000-000000000001'
              AND notes = '${note}';
        `);
        await gotoWhenReady(actorPage, '/LeaveRequests', '#leave-requests-content');

        await loginAndOpenRoster(viewerPage);
        const viewerTargetRow = await ensureEditableRosterRow(viewerPage, 1);
        const viewerTargetSelect = viewerTargetRow.locator('select[name="staffId"]').first();
        await viewerTargetSelect.selectOption(targetStaffId);
        await expect(viewerTargetSelect).toHaveValue(targetStaffId);
        const viewerTargetStaffCell = viewerTargetRow.locator('.slot-staff-cell').first();

        const leaveRow = actorPage.locator('#leave-requests-content article').filter({ hasText: note });

        await expect(leaveRow).toContainText('Pending');
        await expect(viewerPage.locator('#roster-content')).toBeVisible();
        await expect(viewerTargetStaffCell).not.toHaveAttribute('title', /approved unavailable period/i);

        await leaveRow.getByRole('button', { name: 'Approve' }).click();

        await expect(leaveRow).toContainText('Approved');
        await expect
            .poll(async () => await viewerTargetStaffCell.getAttribute('title'), { timeout: E2E_TIMEOUT.liveUpdate })
            .toMatch(/approved unavailable period/i);
        await expect(viewerTargetStaffCell).toHaveAttribute('data-conflict-message', /approved unavailable period/i);

        await actorContext.close();
        await requesterContext.close();
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

        await gotoWhenReady(managerPage, '/Timesheets?showApproved=true', '#timesheet-week-shell');
        await gotoWhenReady(workerPage, '/Timesheets?showApproved=true', '#timesheet-week-shell');

        await createTimesheet(workerPage, '11:15', '15:15');

        const managerEntry = managerPage.locator('#timesheet-day-section-0 .timesheet-entry-card').filter({ hasText: renderedRange });
        const workerEntry = workerPage.locator('#timesheet-day-section-0 .timesheet-entry-card').filter({ hasText: renderedRange });

        await expect(managerEntry).toHaveCount(1);
        await expect(managerEntry.getByRole('button', { name: 'Approve' })).toBeVisible();
        await expect(workerEntry).toHaveCount(1);
        await expect(workerEntry).not.toContainText('Approved');

        await managerEntry.getByRole('button', { name: 'Approve' }).click();

        await expect(managerEntry).toContainText('Approved');
        await expect(workerEntry).toHaveAttribute('data-timesheet-entry-approved', 'true');

        await managerContext.close();
        await workerContext.close();
    });
});
