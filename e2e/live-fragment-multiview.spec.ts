import { expect, Page, test } from '@playwright/test';
import {
    dialogOverlayMountDomId,
    rosterStaffHighlightMemberDomAttr,
} from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady, loginAs, openProfileLeaveSection, openRoster, resetTimesheetDisplayPreferences, runSql, setFlatpickrDate } from './test-helpers';

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

async function showApprovedTimesheets(page: Page) {
    await page.getByRole('button', { name: 'Timesheet settings' }).click();
    const hideApproved = page.locator('label', { hasText: 'Hide approved' });
    if (await hideApproved.locator('input[type="checkbox"]').isChecked()) {
        await hideApproved.click();
    }
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
    await expect(page.locator('#self-service-leave-form-fragment')).toBeVisible();
    await expect(page.locator('#self-service-leave-history-fragment')).toContainText(note);
}

async function createTimesheet(page: Page, startTime: string, endTime: string, staffComment?: string) {
    await page.locator('[data-timesheet-day-add="true"]').first().click();
    if (staffComment !== undefined) {
        await expect(page.locator('#timesheet-entry-create-form')).toBeVisible();
        await page.fill('textarea[name="staffComment"]', staffComment);
    }
    await fillAndSaveTimesheetDialog(page, startTime, endTime);
}

const managerApprovalEntryMarker = 'e2e-live-manager-approval';

function cleanupManagerApprovalEntry() {
    runSql(`
        UPDATE timesheet_entries
        SET deleted_at = NOW(), delete_reason = 'e2e_cleanup', updated_at = NOW()
        WHERE staff_id = 'a1000000-0000-0000-0000-000000000031'
          AND staff_comment = '${managerApprovalEntryMarker}'
          AND deleted_at IS NULL;
    `);
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
    await expect(page.locator(`#${dialogOverlayMountDomId}`)).toBeEmpty();
}

async function openProfileDetailsSection(page: Page) {
    const detailsToggle = page.getByRole('button', { name: 'Profile Details' });
    if ((await detailsToggle.getAttribute('aria-expanded')) !== 'true') {
        await detailsToggle.click();
    }
    await expect(page.locator('#profile-details-form')).toBeVisible({ timeout: E2E_TIMEOUT.action });
}

test.describe('Live fragment multi-view coverage', () => {
    test.afterEach(() => {
        resetTimesheetDisplayPreferences(managerCreds.email);
        resetTimesheetDisplayPreferences(workerCreds.email);
    });
    test.afterEach(() => {
        runSql(`
            UPDATE staff
            SET preferred_name = NULL, updated_at = NOW()
            WHERE id = 'a1000000-0000-0000-0000-000000000031';
        `);
    });

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

        await expect(actorPage.locator('#profile-live-surface [data-bepis-surface="profile"][data-bepis-surface-config]')).toHaveAttribute('data-bepis-surface-config', /profile-details-section/);
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
        const targetStaffId = 'a1000000-0000-0000-0000-000000000031';
        const targetStaffKey = 'staff:a1000000-0000-0000-0000-000000000031';
        const viewerTargetLauncher = viewerPage
            .locator(`[data-roster-shift-launcher="true"][${rosterStaffHighlightMemberDomAttr}="${targetStaffKey}"]`)
            .first();
        await expect(viewerTargetLauncher).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
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

        const approvalResponsePromise = actorPage.waitForResponse((response) =>
            response.request().method() === 'POST' && response.url().includes('/ApproveLeaveRequest'),
        );
        await leaveRow.getByRole('button', { name: 'Approve' }).click();
        const approvalResponse = await approvalResponsePromise;
        expect(approvalResponse.status(), await approvalResponse.text()).toBe(200);
        await approvalResponse.finished();

        await expect(leaveRow).toHaveCount(1, { timeout: E2E_TIMEOUT.liveUpdate });
        await expect(leaveRow).toContainText('Approved');
        await viewerPage.reload();
        await expect(viewerPage.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await expect(viewerTargetStaffCell).toHaveAttribute('title', /approved unavailable period/i, { timeout: E2E_TIMEOUT.liveUpdate });

        await actorContext.close();
        await requesterContext.close();
        await viewerContext.close();
    });

    test('roster suggestion cards materialize once and update another timesheet viewer live', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();
        const rosterSlotId = 'e2000000-0000-0000-0000-000000000901';
        const renderedRange = '6:15–7:15 AM';

        runSql(`
            UPDATE timesheet_entries
            SET deleted_at = NOW(), delete_reason = 'e2e_reset', updated_at = NOW()
            WHERE source_roster_slot_id = '${rosterSlotId}' AND deleted_at IS NULL;

            UPDATE roster_slots
            SET deleted_at = NOW(), delete_reason = 'e2e_reset', updated_at = NOW()
            WHERE id = '${rosterSlotId}' AND deleted_at IS NULL;

            UPDATE roster_weeks
            SET is_live = TRUE, updated_at = NOW()
            WHERE venue_id = 'a1000000-0000-0000-0000-000000000001'
              AND week_offset = 0;

            INSERT INTO roster_slots (
                id,
                roster_day_id,
                staff_id,
                assignment_state,
                roster_week_slot_definition_id,
                slot_sort_order,
                row_index,
                starts_at,
                ends_at,
                timezone,
                shift_type_id,
                deleted_at,
                delete_reason
            )
            SELECT
                '${rosterSlotId}',
                roster_days.id,
                staff.id,
                'staff',
                roster_week_slot_definitions.id,
                0,
                10,
                ((venue_config.week_offset_epoch + (roster_weeks.week_offset * 7) + roster_days.day_offset) + TIME '06:15') AT TIME ZONE venue_config.timezone,
                ((venue_config.week_offset_epoch + (roster_weeks.week_offset * 7) + roster_days.day_offset) + TIME '07:15') AT TIME ZONE venue_config.timezone,
                venue_config.timezone,
                shift_types.id,
                NULL,
                NULL
            FROM roster_weeks
            JOIN roster_days
              ON roster_days.roster_week_id = roster_weeks.id
             AND roster_days.day_offset = 0
            JOIN venue_config
              ON venue_config.venue_id = roster_weeks.venue_id
            JOIN roster_week_slot_definitions
              ON roster_week_slot_definitions.roster_week_id = roster_weeks.id
             AND roster_week_slot_definitions.deleted_at IS NULL
            JOIN users
              ON users.email = '${workerCreds.email}'
            JOIN staff
              ON staff.venue_id = roster_weeks.venue_id
             AND staff.user_id = users.id
             AND staff.is_active = TRUE
            JOIN shift_types
              ON shift_types.venue_id = roster_weeks.venue_id
             AND shift_types.is_active = TRUE
             AND shift_types.archived_at IS NULL
            WHERE roster_weeks.venue_id = 'a1000000-0000-0000-0000-000000000001'
              AND roster_weeks.week_offset = 0
            ORDER BY roster_week_slot_definitions.sort_order, shift_types.created_at
            LIMIT 1
            ON CONFLICT (id) DO UPDATE SET
                roster_day_id = EXCLUDED.roster_day_id,
                staff_id = EXCLUDED.staff_id,
                assignment_state = EXCLUDED.assignment_state,
                roster_week_slot_definition_id = EXCLUDED.roster_week_slot_definition_id,
                row_index = EXCLUDED.row_index,
                starts_at = EXCLUDED.starts_at,
                ends_at = EXCLUDED.ends_at,
                timezone = EXCLUDED.timezone,
                shift_type_id = EXCLUDED.shift_type_id,
                deleted_at = NULL,
                deleted_by_user_id = NULL,
                delete_reason = NULL,
                updated_at = NOW();
        `);

        await loginWorker(actorPage);
        await loginWorker(viewerPage);
        await gotoWhenReady(actorPage, '/Timesheets', '#timesheet-week-shell');
        await gotoWhenReady(viewerPage, '/Timesheets', '#timesheet-week-shell');

        const actorSuggestion = actorPage.locator(`.timesheet-suggestion-card[data-timesheet-suggestion-id="${rosterSlotId}"]`);
        const viewerSuggestion = viewerPage.locator(`.timesheet-suggestion-card[data-timesheet-suggestion-id="${rosterSlotId}"]`);
        await expect(actorSuggestion).toHaveCount(1);
        await expect(actorSuggestion).toHaveClass(/timesheet-entry-card/);
        await expect(actorSuggestion).toHaveCSS('opacity', '1');
        await expect(actorSuggestion).toHaveCSS('border-top-width', '2px');
        await expect(actorSuggestion).toHaveCSS('cursor', 'pointer');
        await expect(actorSuggestion).not.toContainText('Rostered');
        await expect(actorSuggestion).toContainText(renderedRange);
        await expect(actorSuggestion.locator('.timesheet-shape-bar')).toHaveCount(1);
        await expect(actorSuggestion.getByRole('button', { name: 'Create', exact: true })).toBeVisible();
        await expect(actorSuggestion).not.toContainText('Edit first');
        await expect(viewerSuggestion).toHaveCount(1);

        await actorSuggestion.locator('.timesheet-entry-card-link').click();
        await expect(actorPage.locator('#timesheet-suggestion-create-form')).toBeVisible();
        await expect(actorPage.locator('#timesheet-suggestion-create-form select[name="staffId"]')).toHaveCount(0);
        await actorPage.getByRole('button', { name: 'Save', exact: true }).click();

        const actorEntry = actorPage.locator('.timesheet-entry-card:not(.timesheet-suggestion-card)').filter({ hasText: renderedRange });
        const viewerEntry = viewerPage.locator('.timesheet-entry-card:not(.timesheet-suggestion-card)').filter({ hasText: renderedRange });
        await expect(actorSuggestion).toHaveCount(0);
        await expect(actorEntry).toHaveCount(1);
        await expect(actorEntry).toHaveCSS('border-top-width', '1px');
        await expect(actorEntry).not.toContainText('Approved');
        await expect(viewerSuggestion).toHaveCount(0, { timeout: E2E_TIMEOUT.liveUpdate });
        await expect(viewerEntry).toHaveCount(1, { timeout: E2E_TIMEOUT.liveUpdate });

        runSql(`
            UPDATE timesheet_entries
            SET deleted_at = NOW(), delete_reason = 'e2e_cleanup', updated_at = NOW()
            WHERE source_roster_slot_id = '${rosterSlotId}' AND deleted_at IS NULL;
            UPDATE roster_slots
            SET deleted_at = NOW(), delete_reason = 'e2e_cleanup', updated_at = NOW()
            WHERE id = '${rosterSlotId}' AND deleted_at IS NULL;
        `);

        await actorContext.close();
        await viewerContext.close();
    });

    test('manager approval updates the worker timesheet page live', async ({ browser }) => {
        const managerContext = await browser.newContext();
        const workerContext = await browser.newContext();
        const managerPage = await managerContext.newPage();
        const workerPage = await workerContext.newPage();
        const renderedRange = '11:15 AM–3:15 PM';

        cleanupManagerApprovalEntry();
        resetTimesheetDisplayPreferences(managerCreds.email);
        resetTimesheetDisplayPreferences(workerCreds.email);
        try {
            await loginManager(managerPage);
            await loginWorker(workerPage);

            await gotoWhenReady(managerPage, '/Timesheets', '#timesheet-week-shell');
            await gotoWhenReady(workerPage, '/Timesheets', '#timesheet-week-shell');
            await showApprovedTimesheets(managerPage);
            await showApprovedTimesheets(workerPage);

            await createTimesheet(workerPage, '11:15', '15:15', managerApprovalEntryMarker);

            const managerEntry = managerPage.locator('#timesheet-day-section-0 .timesheet-entry-card').filter({ hasText: managerApprovalEntryMarker });
            const workerEntry = workerPage.locator('#timesheet-day-section-0 .timesheet-entry-card').filter({ hasText: managerApprovalEntryMarker });

            await expect(managerEntry).toHaveCount(1);
            await expect(managerEntry).toContainText(renderedRange);
            await expect(managerEntry.getByRole('button', { name: 'Approve' })).toBeVisible();
            await expect(workerEntry).toHaveCount(1);
            await expect(workerEntry).not.toContainText('Approved');

            await managerEntry.getByRole('button', { name: 'Approve' }).click();

            await expect(managerEntry).toContainText('Approved');
            await expect(workerEntry).toHaveAttribute('data-timesheet-entry-approved', 'true', { timeout: E2E_TIMEOUT.liveUpdate });
        } finally {
            cleanupManagerApprovalEntry();
            resetTimesheetDisplayPreferences(managerCreds.email);
            resetTimesheetDisplayPreferences(workerCreds.email);
            await managerContext.close();
            await workerContext.close();
        }
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
        await gotoWhenReady(timesheetPage, '/Timesheets', '#timesheet-week-shell');

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
