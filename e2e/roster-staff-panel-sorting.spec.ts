import { test, expect, type Page } from '@playwright/test';
import {
    parseRosterStaffPanelSortRow,
    rosterStaffHighlightSourceDomAttr,
    rosterStaffPanelSortControlDomAttr,
    rosterStaffPanelSortRowDomAttr,
    type RosterStaffPanelSortRow,
} from '../frontend/ts/generated/contracts';
import { assignRosterShiftStaff, existingRosterShiftLaunchers, openRoster } from './test-helpers';

async function loginAndOpenRoster(page: Page) {
    await openRoster(page, { email: 'e2e-test@example.com' });
    await expect(page.locator('#roster-staff-panel-fragment')).toBeVisible();
}

async function readPanelRows(page: Page): Promise<RosterStaffPanelSortRow[]> {
    const rawRows = await page
        .locator(`#roster-staff-panel-fragment [${rosterStaffPanelSortRowDomAttr}]`)
        .evaluateAll((rows, rowAttribute) => rows.map((row) => row.getAttribute(rowAttribute)), rosterStaffPanelSortRowDomAttr);
    return rawRows.map((raw) => {
        if (raw === null) throw new Error(`Missing ${rosterStaffPanelSortRowDomAttr}`);
        return parseRosterStaffPanelSortRow(JSON.parse(raw) as unknown);
    });
}

function compareText(leftValue: string, rightValue: string) {
    return leftValue.localeCompare(rightValue, undefined, { sensitivity: 'base' });
}

function sortControl(page: Page, key: 'name' | 'role' | 'shifts') {
    return page.locator(`button[${rosterStaffPanelSortControlDomAttr}="${key}"]`);
}

test.describe('Roster staff panel sorting', () => {
    test('sorts by name, role, and shifts with asc/desc toggles', async ({ page }) => {
        await loginAndOpenRoster(page);

        const sortByName = sortControl(page, 'name');
        const sortByRole = sortControl(page, 'role');
        const sortByShifts = sortControl(page, 'shifts');

        const baselineRows = await readPanelRows(page);

        await sortByName.click();
        await expect(sortByName).toHaveAttribute('aria-sort', 'descending');
        const nameDescRows = await readPanelRows(page);
        const expectedNameDesc = [...baselineRows].sort((leftRow, rightRow) => {
            const nameResult = compareText(rightRow.staffName, leftRow.staffName);
            if (nameResult !== 0) return nameResult;
            return leftRow.staffRowKey < rightRow.staffRowKey ? -1 : leftRow.staffRowKey > rightRow.staffRowKey ? 1 : 0;
        });
        expect(nameDescRows.map((row) => row.staffName)).toEqual(expectedNameDesc.map((row) => row.staffName));

        await sortByRole.click();
        await expect(sortByRole).toHaveAttribute('aria-sort', 'ascending');
        const roleAscRows = await readPanelRows(page);
        const expectedRoleAsc = [...baselineRows].sort((leftRow, rightRow) => {
            const roleResult = compareText(leftRow.staffRole, rightRow.staffRole);
            if (roleResult !== 0) return roleResult;
            const nameResult = compareText(leftRow.staffName, rightRow.staffName);
            if (nameResult !== 0) return nameResult;
            return leftRow.staffRowKey < rightRow.staffRowKey ? -1 : leftRow.staffRowKey > rightRow.staffRowKey ? 1 : 0;
        });
        expect(roleAscRows.map((row) => `${row.staffRole}|${row.staffName}`)).toEqual(
            expectedRoleAsc.map((row) => `${row.staffRole}|${row.staffName}`),
        );

        const targetStaffId = 'a0000000-0000-0000-0000-000000000101';
        const targetStaffKey = 'staff:a0000000-0000-0000-0000-000000000101';
        const targetRow = page.locator(
            `#roster-staff-panel-fragment [${rosterStaffPanelSortRowDomAttr}][${rosterStaffHighlightSourceDomAttr}="${targetStaffKey}"]`,
        );
        const targetRaw = await targetRow.getAttribute(rosterStaffPanelSortRowDomAttr);
        expect(targetRaw).toBeTruthy();
        const targetStaffName = parseRosterStaffPanelSortRow(JSON.parse(targetRaw ?? 'null') as unknown).staffName;

        await assignRosterShiftStaff(page, existingRosterShiftLaunchers(page).first(), targetStaffId);

        await expect
            .poll(async () => {
                const rows = await readPanelRows(page);
                return rows.find((row) => row.staffName === targetStaffName)?.assignedShifts ?? 0;
            })
            .toBe(1);
        // The actor-local refresh and websocket invalidation may coalesce into
        // consecutive authoritative panel replacements. Sort only after those
        // HTMX requests settle; a replacement intentionally resets sort state.
        await page.waitForLoadState('networkidle');

        await sortByShifts.click();
        await expect(sortByShifts).toHaveAttribute('aria-sort', 'ascending');
        const shiftsAscRows = await readPanelRows(page);
        const expectedShiftsAsc = [...shiftsAscRows].sort((leftRow, rightRow) => {
            const assignedResult = leftRow.assignedShifts - rightRow.assignedShifts;
            if (assignedResult !== 0) return assignedResult;
            const idealResult = leftRow.idealShifts - rightRow.idealShifts;
            if (idealResult !== 0) return idealResult;
            const nameResult = compareText(leftRow.staffName, rightRow.staffName);
            if (nameResult !== 0) return nameResult;
            return leftRow.staffRowKey < rightRow.staffRowKey ? -1 : leftRow.staffRowKey > rightRow.staffRowKey ? 1 : 0;
        });
        expect(shiftsAscRows.map((row) => `${row.assignedShifts}|${row.idealShifts}|${row.staffName}`)).toEqual(
            expectedShiftsAsc.map((row) => `${row.assignedShifts}|${row.idealShifts}|${row.staffName}`),
        );

        await sortByShifts.click();
        await expect(sortByShifts).toHaveAttribute('aria-sort', 'descending');
        const shiftsDescRows = await readPanelRows(page);
        const expectedShiftsDesc = [...shiftsAscRows].sort((leftRow, rightRow) => {
            const assignedResult = rightRow.assignedShifts - leftRow.assignedShifts;
            if (assignedResult !== 0) return assignedResult;
            const idealResult = rightRow.idealShifts - leftRow.idealShifts;
            if (idealResult !== 0) return idealResult;
            const nameResult = compareText(leftRow.staffName, rightRow.staffName);
            if (nameResult !== 0) return nameResult;
            return leftRow.staffRowKey < rightRow.staffRowKey ? -1 : leftRow.staffRowKey > rightRow.staffRowKey ? 1 : 0;
        });
        expect(shiftsDescRows.map((row) => `${row.assignedShifts}|${row.idealShifts}|${row.staffName}`)).toEqual(
            expectedShiftsDesc.map((row) => `${row.assignedShifts}|${row.idealShifts}|${row.staffName}`),
        );
    });
});
