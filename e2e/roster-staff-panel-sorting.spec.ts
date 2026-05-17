import { test, expect } from '@playwright/test';
import { openRoster } from './test-helpers';

async function loginAndOpenRoster(page) {
    await openRoster(page, { email: 'e2e-test@example.com' });
    await expect(page.locator('#roster-staff-panel-fragment')).toBeVisible();
}

async function readPanelRows(page) {
    return page.locator('#roster-staff-panel-fragment .roster-staff-panel-entry').evaluateAll((rows) => {
        return rows.map((row) => {
            const element = row;
            const assigned = Number.parseInt(element.getAttribute('data-roster-staff-assigned') || '0', 10);
            const ideal = Number.parseInt(element.getAttribute('data-roster-staff-ideal') || '0', 10);
            return {
                name: element.getAttribute('data-roster-staff-name') || '',
                role: element.getAttribute('data-roster-staff-role') || '',
                assigned,
                ideal,
            };
        });
    });
}

function compareText(leftValue: string, rightValue: string) {
    return leftValue.localeCompare(rightValue, undefined, { sensitivity: 'base' });
}

function panelNameFromOptionLabel(label: string) {
    const [lastName, firstName] = label.split(',').map((part) => part.trim());
    if (!firstName || !lastName) return label.trim();
    return `${firstName} ${lastName}`;
}

test.describe('Roster staff panel sorting', () => {
    test('sorts by name, role, and shifts with asc/desc toggles', async ({ page }) => {
        await loginAndOpenRoster(page);

        const sortByName = page.locator('button[data-roster-staff-sort-key="name"]');
        const sortByRole = page.locator('button[data-roster-staff-sort-key="role"]');
        const sortByShifts = page.locator('button[data-roster-staff-sort-key="shifts"]');

        const baselineRows = await readPanelRows(page);

        await sortByName.click();
        await expect(sortByName).toHaveAttribute('aria-sort', 'descending');
        const nameDescRows = await readPanelRows(page);
        const expectedNameDesc = [...baselineRows].sort((leftRow, rightRow) => compareText(rightRow.name, leftRow.name));
        expect(nameDescRows.map((row) => row.name)).toEqual(expectedNameDesc.map((row) => row.name));

        await sortByRole.click();
        await expect(sortByRole).toHaveAttribute('aria-sort', 'ascending');
        const roleAscRows = await readPanelRows(page);
        const expectedRoleAsc = [...baselineRows].sort((leftRow, rightRow) => {
            const roleResult = compareText(leftRow.role, rightRow.role);
            if (roleResult !== 0) return roleResult;
            return compareText(leftRow.name, rightRow.name);
        });
        expect(roleAscRows.map((row) => `${row.role}|${row.name}`)).toEqual(
            expectedRoleAsc.map((row) => `${row.role}|${row.name}`),
        );

        const assignmentSelect = page.locator('select[name="staffId"]').first();
        await assignmentSelect.selectOption('a0000000-0000-0000-0000-000000000101');
        const selectedStaffName = panelNameFromOptionLabel(
            (await assignmentSelect.locator('option:checked').textContent()) ?? '',
        );

        await expect
            .poll(async () => {
                const rows = await readPanelRows(page);
                return rows.find((row) => row.name === selectedStaffName)?.assigned ?? 0;
            })
            .toBe(1);

        await sortByShifts.click();
        await expect(sortByShifts).toHaveAttribute('aria-sort', 'ascending');
        const shiftsAscRows = await readPanelRows(page);
        const expectedShiftsAsc = [...shiftsAscRows].sort((leftRow, rightRow) => {
            const assignedResult = leftRow.assigned - rightRow.assigned;
            if (assignedResult !== 0) return assignedResult;
            const idealResult = leftRow.ideal - rightRow.ideal;
            if (idealResult !== 0) return idealResult;
            return compareText(leftRow.name, rightRow.name);
        });
        expect(shiftsAscRows.map((row) => `${row.assigned}|${row.ideal}|${row.name}`)).toEqual(
            expectedShiftsAsc.map((row) => `${row.assigned}|${row.ideal}|${row.name}`),
        );

        await sortByShifts.click();
        await expect(sortByShifts).toHaveAttribute('aria-sort', 'descending');
        const shiftsDescRows = await readPanelRows(page);
        const expectedShiftsDesc = [...shiftsAscRows].sort((leftRow, rightRow) => {
            const assignedResult = rightRow.assigned - leftRow.assigned;
            if (assignedResult !== 0) return assignedResult;
            const idealResult = rightRow.ideal - leftRow.ideal;
            if (idealResult !== 0) return idealResult;
            return compareText(leftRow.name, rightRow.name);
        });
        expect(shiftsDescRows.map((row) => `${row.assigned}|${row.ideal}|${row.name}`)).toEqual(
            expectedShiftsDesc.map((row) => `${row.assigned}|${row.ideal}|${row.name}`),
        );
    });
});
