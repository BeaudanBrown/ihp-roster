import { test, expect, type Page } from '@playwright/test';
import { dialogCloseDomAttr, dialogOverlayMountDomId, toggleRootDomAttr, toggleTransportDomAttr } from '../frontend/ts/generated/contracts';
import {
    addRowToRosterDay,
    assignRosterShiftStaff,
    editableRosterRows,
    firstEditableRosterDaySection,
    openRoster,
    openRosterSettings,
    openRosterShiftDialog,
    querySql,
    rosterShiftDialogStaffOptionValues,
} from './test-helpers';

async function loginAndOpenRoster(page: Page) {
    await openRoster(page, { weekOffset: 1 });
}

async function setHideAlreadyAssignedToday(page: Page) {
    await openRosterSettings(page);
    const root = page.locator(`[${toggleRootDomAttr}]`).filter({ hasText: 'Double shifts' });
    await expect(root).toBeVisible();
    const checkbox = root.locator('#hide-staff-assigned-today');
    if (!(await checkbox.isChecked())) {
        const responsePromise = page.waitForResponse((response) => response.request().method() === 'POST' && response.url().includes('/UpdateRosterAssignmentFilters'));
        await page.evaluate(({ rootAttribute, transportAttribute }) => {
            const rootElement = Array.from(document.querySelectorAll(`[${rootAttribute}]`))
                .find((element) => element.textContent?.includes('Double shifts'));
            if (!(rootElement instanceof HTMLElement)) throw new Error('Double shifts toggle missing');
            const checkboxInput = rootElement.querySelector('input[type="checkbox"]');
            if (!(checkboxInput instanceof HTMLInputElement)) throw new Error('Double shifts checkbox missing');
            checkboxInput.click();
            const transport = rootElement.querySelector(`[${transportAttribute}][name="hideStaffAlreadyAssignedToday"]`);
            if (!(transport instanceof HTMLInputElement) || transport.value !== 'true') throw new Error('Double shifts transport did not synchronize');
        }, { rootAttribute: toggleRootDomAttr, transportAttribute: toggleTransportDomAttr });
        const response = await responsePromise;
        expect(response.status(), await response.text()).toBe(200);
        await response.finished();
    }
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

        const targetDaySectionId = await daySection.getAttribute('id');
        const targetRosterDayId = targetDaySectionId?.replace('roster-day-section-', '');
        expect(targetRosterDayId).toBeTruthy();
        const firstRowLauncher = rows.nth(0).locator('[data-roster-shift-launcher="true"]').first();
        await openRosterShiftDialog(page, firstRowLauncher);
        const staffValues = await rosterShiftDialogStaffOptionValues(page);
        const currentStaffId = await page.locator('#roster-shift-staff-id').inputValue();
        await page.locator(`[${dialogCloseDomAttr}]`).first().click();
        await expect(page.locator(`#${dialogOverlayMountDomId}`)).toBeEmpty();

        const assignedStaffId = currentStaffId || staffValues[0];
        const alternateStaffId = staffValues.find((value) => value !== assignedStaffId);
        expect(assignedStaffId).toBeTruthy();
        expect(alternateStaffId).toBeTruthy();

        if (!currentStaffId) {
            await assignRosterShiftStaff(page, firstRowLauncher, assignedStaffId);
        }

        const secondRowLauncher = rows.nth(1).locator('[data-roster-shift-launcher="true"]').first();
        await assignRosterShiftStaff(page, secondRowLauncher, alternateStaffId!);

        await setHideAlreadyAssignedToday(page);
        const assignmentCount = Number(querySql(`
            SELECT COUNT(*)
            FROM roster_slots slots
            WHERE slots.roster_day_id = '${targetRosterDayId}'
              AND slots.staff_id = '${assignedStaffId}'
              AND slots.deleted_at IS NULL;
        `));
        expect(assignmentCount).toBeGreaterThan(0);
        const secondDialogHref = await secondRowLauncher.getAttribute('hx-get');
        expect(secondDialogHref).toBeTruthy();
        await secondRowLauncher.evaluate((launcher, href) => launcher.setAttribute('hx-get', `${href}${href?.includes('?') ? '&' : '?'}hideStaffAlreadyAssignedToday=true`), secondDialogHref);
        await openRosterShiftDialog(page, secondRowLauncher);
        const selectedSecondStaffId = await page.locator('#roster-shift-staff-id').inputValue();
        expect(selectedSecondStaffId).toBe(alternateStaffId);
        await expect(page.locator(`#roster-shift-staff-id option[value="${assignedStaffId}"]`)).toHaveCount(0);
        await page.locator(`[${dialogCloseDomAttr}]`).first().click();
    });

});
