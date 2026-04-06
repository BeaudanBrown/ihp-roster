import { test, expect } from '@playwright/test';
import { gotoWhenReady } from './test-helpers';

async function loginAndOpenRoster(page) {
    await gotoWhenReady(page, '/NewSession', '#email');
    await page.fill('#email', 'e2e-test@example.com');
    await page.fill('#password', 'test-password-123');
    await page.click('button[type="submit"]');

    await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/, { timeout: 60000 });
    await expect(page.locator('#roster-content')).toBeVisible({ timeout: 60000 });
}

async function ensureSecondRosterRow(page) {
    const editableRows = page.locator('tr[data-roster-row]').filter({ has: page.locator('select[name="staffId"]') });
    if (await editableRows.count() >= 2) return;

    await page.locator('[data-roster-day-add="true"]').first().click();
    await expect(editableRows).toHaveCount(2);
}

async function assignStaffToRow(page, rowIndex, staffId) {
    const row = page.locator('tr[data-roster-row]').filter({ has: page.locator('select[name="staffId"]') }).nth(rowIndex);
    const select = row.locator('select[name="staffId"]');
    await select.selectOption(staffId);
    await expect(select).toHaveValue(staffId);
}

async function blurActiveRosterInput(page) {
    await page.evaluate(() => {
        const activeElement = document.activeElement;
        if (activeElement instanceof HTMLElement) {
            activeElement.blur();
        }
    });
}

async function commitRosterEdit(page) {
    await blurActiveRosterInput(page);
    await page.waitForTimeout(300);
}

async function normalizeRosterForDuplicateConflict(actorPage) {
    const alphaCrewStaffId = 'a1000000-0000-0000-0000-000000000031';
    const alphaCrewEntry = actorPage
        .locator('#roster-staff-panel-fragment .roster-staff-panel-entry')
        .filter({ hasText: 'Alpha Crew' })
        .first();

    await ensureSecondRosterRow(actorPage);
    await assignStaffToRow(actorPage, 0, alphaCrewStaffId);
    await commitRosterEdit(actorPage);
    await assignStaffToRow(actorPage, 1, '');
    await commitRosterEdit(actorPage);
    await expect(alphaCrewEntry).toContainText('1');
}

function duplicateConflictCells(page) {
    return page.locator('.slot-staff-cell.conflict-critical');
}

test.describe('Roster duplicate conflicts', () => {
    test.describe.configure({ retries: 0 });

    test('actor and viewer both keep duplicate conflict highlighting without breaking the roster grid', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await loginAndOpenRoster(actorPage);
        await normalizeRosterForDuplicateConflict(actorPage);

        await loginAndOpenRoster(viewerPage);
        await expect(
            viewerPage.locator('tr[data-roster-row]').filter({ has: viewerPage.locator('select[name="staffId"]') }),
        ).toHaveCount(2);

        const alphaCrewStaffId = 'a1000000-0000-0000-0000-000000000031';
        const alphaCrewEntry = actorPage
            .locator('#roster-staff-panel-fragment .roster-staff-panel-entry')
            .filter({ hasText: 'Alpha Crew' })
            .first();

        await assignStaffToRow(actorPage, 1, alphaCrewStaffId);
        await commitRosterEdit(actorPage);
        await expect(alphaCrewEntry).toContainText('2');
        await expect
            .poll(async () => duplicateConflictCells(actorPage).count(), { timeout: 15000 })
            .toBe(2);
        await expect
            .poll(async () => duplicateConflictCells(viewerPage).count(), { timeout: 15000 })
            .toBe(2);

        const viewerGridState = await viewerPage.locator('table.roster-grid').evaluate((table) => {
            const bodyRows = Array.from(table.querySelectorAll('tbody > tr[data-roster-row]'));
            const outsideRows = Array.from(document.querySelectorAll('tr[data-roster-row]')).filter(
                (row) => !row.closest('tbody'),
            );
            return {
                bodyRowCount: bodyRows.length,
                outsideRowCount: outsideRows.length,
                editableBodyRowCount: bodyRows.filter((row) => row.querySelector('select[name="staffId"]')).length,
                firstRowCellCount: bodyRows[0]?.children.length ?? 0,
                secondRowCellCount: bodyRows[1]?.children.length ?? 0,
                selectCount: table.querySelectorAll('select[name="staffId"]').length,
            };
        });

        expect(viewerGridState.outsideRowCount).toBe(0);
        expect(viewerGridState.editableBodyRowCount).toBe(2);
        expect(viewerGridState.selectCount).toBe(2);
        expect(viewerGridState.bodyRowCount).toBeGreaterThanOrEqual(2);
        expect(viewerGridState.firstRowCellCount).toBeGreaterThanOrEqual(3);

        await actorContext.close();
        await viewerContext.close();
    });
});
