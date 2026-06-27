import { test, expect, type Page } from '@playwright/test';
import {
    addRowToRosterDay,
    assignRosterShiftStaff,
    editableRosterRows,
    firstEditableRosterDaySection,
    openRoster,
    openRosterShiftDialog,
    rosterShiftDialogStaffOptionValues,
} from './test-helpers';

async function loginAndOpenRoster(page: Page) {
    await openRoster(page, { weekOffset: 1 });
}

async function setHideAlreadyAssignedToday(page: Page) {
    await page.getByLabel('Roster settings').click();
    await Promise.all([
        page.waitForResponse((response) => response.request().method() === 'POST' && response.url().includes('/UpdateRosterAssignmentFilters')),
        page.getByLabel('Double shifts').check({ force: true }),
    ]);
    await expect(page.locator('#roster-content')).toBeVisible();
}

test.describe('Roster assignment filters', () => {
    test('updates other staff dropdowns immediately when already-assigned-today filtering is active', async ({ page }) => {
        await loginAndOpenRoster(page);

        const daySection = firstEditableRosterDaySection(page);
        const rows = editableRosterRows(daySection);
        if ((await rows.count()) < 2) {
            await addRowToRosterDay(daySection);
            await expect
                .poll(async () => await editableRosterRows(daySection).count())
                .toBe(2);
        }
        expect(await rows.count()).toBeGreaterThanOrEqual(2);

        const firstRowLauncher = rows.nth(0).locator('[data-roster-shift-launcher="true"]').first();
        await openRosterShiftDialog(page, firstRowLauncher);
        const staffValues = await rosterShiftDialogStaffOptionValues(page);
        await page.locator('[data-dialog-overlay-close="true"]').first().click();
        await expect(page.locator('#dialog-overlay-mount')).toBeEmpty();

        const assignedStaffId = await firstRowLauncher.getAttribute('data-roster-staff-id') || staffValues[0];
        const alternateStaffId = staffValues.find((value) => value !== assignedStaffId);
        expect(assignedStaffId).toBeTruthy();
        expect(alternateStaffId).toBeTruthy();

        if ((await firstRowLauncher.getAttribute('data-roster-staff-id')) !== assignedStaffId) {
            await assignRosterShiftStaff(page, firstRowLauncher, assignedStaffId);
        }

        const secondRowLauncher = rows.nth(1).locator('[data-roster-shift-launcher="true"]').first();
        if ((await secondRowLauncher.getAttribute('data-roster-staff-id')) !== alternateStaffId) {
            await assignRosterShiftStaff(page, secondRowLauncher, alternateStaffId!);
        }

        await setHideAlreadyAssignedToday(page);
        await openRosterShiftDialog(page, secondRowLauncher);
        await expect
            .poll(async () => (await rosterShiftDialogStaffOptionValues(page)).includes(assignedStaffId))
            .toBe(false);
        await page.locator('[data-dialog-overlay-close="true"]').first().click();
    });

});
