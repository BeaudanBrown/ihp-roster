import { expect, Page, test } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady, loginAs, openProfileLeaveSection, openRoster, runSql, setFlatpickrDate } from './test-helpers';

const e2eRosterPath = '/ShowRosterWeek?weekOffset=0&rosterGroupId=a1000000-0000-0000-0000-000000000211';

const managerCreds = {
    email: 'e2e-test@example.com',
    password: 'test-password-123',
};

const workerCreds = {
    email: 'e2e-worker@example.com',
    password: 'test-password-123',
};

async function loginManager(page: Page) {
    await loginAs(page, managerCreds.email, managerCreds.password);
}

async function loginWorker(page: Page) {
    await loginAs(page, workerCreds.email, workerCreds.password);
}

async function loginAndOpenRoster(page: Page) {
    await openRoster(page, { email: managerCreds.email, password: managerCreds.password });
    await expect(page.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
}

async function currentBroadLeaveRange(page: Page) {
    return page.evaluate(() => {
        const now = new Date();
        const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
        const end = new Date(start);
        start.setUTCDate(start.getUTCDate() - 14);
        end.setUTCDate(end.getUTCDate() + 14);
        return {
            startDate: start.toISOString().slice(0, 10),
            endDate: end.toISOString().slice(0, 10),
        };
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
    await fillAndSaveTimesheetDialog(page, startTime, endTime);
}

async function createTimesheetForDaySection(page: Page, dayOffset: string, startTime: string, endTime: string) {
    await page.locator(`#timesheet-day-section-${dayOffset} [data-timesheet-day-add="true"]`).click();
    await fillAndSaveTimesheetDialog(page, startTime, endTime);
}

async function fillAndSaveTimesheetDialog(page: Page, startTime: string, endTime: string) {
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

async function openProfileDetailsSection(page: Page) {
    const detailsToggle = page.getByRole('button', { name: 'Profile Details' });
    if ((await detailsToggle.getAttribute('aria-expanded')) !== 'true') {
        await detailsToggle.click();
    }
    await expect(page.locator('#profile-details-form')).toBeVisible({ timeout: E2E_TIMEOUT.action });
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

        const { startDate, endDate } = await currentBroadLeaveRange(workerPage);

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

    test('profile save updates another open profile tab live while actor gets an immediate fragment', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();
        const preferredName = `Live ${Date.now()}`;

        await loginWorker(actorPage);
        await loginWorker(viewerPage);

        await gotoWhenReady(actorPage, '/EditProfile', '#profile-live-surface');
        await gotoWhenReady(viewerPage, '/EditProfile', '#profile-live-surface');

        await expect(actorPage.locator('#profile-live-surface [data-bepis-surface-config]')).toHaveAttribute('data-bepis-surface-config', /profile-details-section/);
        await openProfileDetailsSection(actorPage);
        await openProfileDetailsSection(viewerPage);
        await expect(viewerPage.locator('#preferredName')).not.toHaveValue(preferredName);

        await actorPage.fill('#preferredName', preferredName);
        await Promise.all([
            actorPage.waitForResponse((response) => response.url().includes('/UpdateProfile') && response.request().method() === 'POST'),
            actorPage.locator('#profile-details-form button[type="submit"]').click(),
        ]);

        await expect(actorPage.locator('#profile-content-fragment')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(actorPage.locator('#preferredName')).toHaveValue(preferredName);
        await expect(viewerPage.locator('#preferredName')).toHaveValue(preferredName, { timeout: E2E_TIMEOUT.liveUpdate });

        await actorContext.close();
        await viewerContext.close();
    });

    test('leave approval exposes the new roster conflict state after viewer refresh', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const requesterContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const requesterPage = await requesterContext.newPage();
        const viewerPage = await viewerContext.newPage();
        const note = 'Alpha leave request';

        await loginManager(actorPage);
        runSql(`
            UPDATE leave_requests
            SET status = 'denied', deleted_at = NULL, updated_at = NOW()
            WHERE venue_id = 'a1000000-0000-0000-0000-000000000001'
              AND notes = '${note}';
        `);
        await loginAndOpenRoster(viewerPage);
        const viewerTargetLauncher = viewerPage
            .locator('[data-roster-shift-launcher="true"][data-roster-staff-id]:not([data-roster-staff-id=""])')
            .first();
        await expect(viewerTargetLauncher).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        const targetStaffId = await viewerTargetLauncher.getAttribute('data-roster-staff-id');
        expect(targetStaffId).toBeTruthy();
        const viewerTargetStaffCell = viewerTargetLauncher.locator('.slot-staff-cell').first();

        const { startDate, endDate } = await currentBroadLeaveRange(actorPage);
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

        const leaveRow = actorPage.locator('#leave-requests-content article').filter({ hasText: note });

        await expect(leaveRow).toContainText('Pending');
        await expect(viewerPage.locator('#roster-content')).toBeVisible();
        await expect(viewerTargetStaffCell).not.toHaveAttribute('title', /approved unavailable period/i);

        await leaveRow.getByRole('button', { name: 'Approve' }).click();

        await expect(leaveRow).toContainText('Approved');
        await viewerPage.reload();
        await expect(viewerPage.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await expect(viewerTargetStaffCell).toHaveAttribute('title', /approved unavailable period/i, { timeout: E2E_TIMEOUT.liveUpdate });
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
        const renderedRange = '11:15 AM–3:15 PM';

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

    test('worker roster quick timesheet card and timesheet page refresh each other live', async ({ browser }) => {
        const rosterContext = await browser.newContext();
        const timesheetContext = await browser.newContext();
        const rosterPage = await rosterContext.newPage();
        const timesheetPage = await timesheetContext.newPage();
        const rosterCreatedRange = '1:15–4:15 PM';
        const timesheetCreatedRange = '4:30–7:30 PM';

        await loginWorker(rosterPage);
        await loginWorker(timesheetPage);

        await gotoWhenReady(rosterPage, e2eRosterPath, '#roster-staff-self-service-timesheet-live-surface');
        await gotoWhenReady(timesheetPage, '/Timesheets?showApproved=true', '#timesheet-week-shell');

        const rosterDay = rosterPage.locator('#roster-staff-self-service-timesheet-live-surface [data-timesheet-day-offset]').first();
        const dayOffset = await rosterDay.getAttribute('data-timesheet-day-offset');
        expect(dayOffset).toBeTruthy();

        await createTimesheetForDaySection(rosterPage, dayOffset!, '13:15', '16:15');

        await expect(rosterPage.locator('#roster-staff-self-service-timesheet-live-surface')).toContainText(rosterCreatedRange);
        await expect(timesheetPage.locator(`#timesheet-day-section-${dayOffset}`)).toContainText(rosterCreatedRange, { timeout: E2E_TIMEOUT.liveUpdate });

        await createTimesheetForDaySection(timesheetPage, dayOffset!, '16:30', '19:30');

        await expect(timesheetPage.locator(`#timesheet-day-section-${dayOffset}`)).toContainText(timesheetCreatedRange);
        await expect(rosterPage.locator('#roster-staff-self-service-timesheet-live-surface')).toContainText(rosterCreatedRange);

        await rosterContext.close();
        await timesheetContext.close();
    });
});
