import { test, expect } from '@playwright/test';
import { openRoster } from './test-helpers';

async function loginAndOpenRoster(page) {
    await openRoster(page);
}

async function openRosterWeekOffset(page, weekOffset) {
    await openRoster(page, { weekOffset });
    await expect(page.locator('#roster-week-shell')).toHaveAttribute(
        'data-live-update-week-offset',
        String(weekOffset),
    );
}

async function expectAutoCreatedDraftWeek(page) {
    await expect(page.locator('#roster-content')).toBeVisible();
    await expect(page.locator('tr[data-roster-row]')).toHaveCount(28);
    await expect(page.locator('.form-check-input[type="checkbox"]').first()).not.toBeChecked();
    await expect(page.getByRole('button', { name: 'Create Draft Roster' })).toHaveCount(0);
}

async function selectStaffForRow(page, rowIndex, staffId) {
    const row = page.locator('tr[data-roster-row]').filter({ has: page.locator('select[name="staffId"]') }).nth(rowIndex);
    const select = row.locator('select[name="staffId"]').first();
    await select.selectOption(staffId);
    await expect(select).toHaveValue(staffId);
}

function managerEntry(page) {
    return page
        .locator('#roster-staff-panel-fragment .roster-staff-panel-entry[data-roster-staff-role="Manager"]')
        .first();
}

function firstViewerRow(page) {
    return page.locator('tbody[data-roster-day-section="true"]').first().locator('tr[data-roster-row]').first();
}

async function expectViewerRowAssignmentApplied(page) {
    await expect(firstViewerRow(page)).toContainText(/E2E|Live|Fragments/, { timeout: 15000 });
}

async function copyPreviousWeek(page) {
    page.once('dialog', (dialog) => dialog.accept());
    await page.getByRole('button', { name: 'Copy Previous Week' }).click();
    await expect(page.locator('#roster-week-shell')).toBeVisible();
}

async function normalizeLiveFragmentRoster(page) {
    const alphaCrewStaffId = 'a1000000-0000-0000-0000-000000000031';
    const managerPanelEntry = managerEntry(page);

    await selectStaffForRow(page, 0, alphaCrewStaffId);
    await expect(managerPanelEntry).toContainText('0');
}

test.describe('Roster live fragments', () => {
    test.setTimeout(120000);

    test('updates another viewer live after a slot assignment changes', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await loginAndOpenRoster(actorPage);
        await normalizeLiveFragmentRoster(actorPage);
        await loginAndOpenRoster(viewerPage);

        const actorManagerEntry = managerEntry(actorPage);
        const viewerManagerEntry = managerEntry(viewerPage);

        await expect(actorManagerEntry).toContainText('0');
        await expect(viewerManagerEntry).toContainText('0');

        const assignmentSelect = actorPage.locator('tr[data-roster-row]').filter({ has: actorPage.locator('select[name="staffId"]') }).first().locator('select[name="staffId"]').first();
        await assignmentSelect.selectOption('a0000000-0000-0000-0000-000000000101');

        await expect(actorManagerEntry).toContainText('1');
        await expect(viewerManagerEntry).toContainText('1');

        await actorContext.close();
        await viewerContext.close();
    });

    test('auto-creates a future draft week on navigation without exposing a separate create action', async ({ page }) => {
        await openRosterWeekOffset(page, 2);
        await expectAutoCreatedDraftWeek(page);
    });

    test('updates another manager live after copying the previous week into an auto-created draft week', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await openRosterWeekOffset(actorPage, 2);
        await openRosterWeekOffset(viewerPage, 2);

        await expectAutoCreatedDraftWeek(actorPage);
        await expectAutoCreatedDraftWeek(viewerPage);
        await expect(viewerPage.locator('input[name="note"][value="A1"]')).toHaveCount(0);
        await expect(viewerPage.locator('input[name="note"][value="A2"]')).toHaveCount(0);

        await copyPreviousWeek(actorPage);

        await expect(actorPage.locator('input[name="note"][value="A1"]')).toBeVisible();
        await expect(actorPage.locator('input[name="note"][value="A2"]')).toBeVisible();
        await expect(viewerPage.locator('input[name="note"][value="A1"]')).toBeVisible({ timeout: 15000 });
        await expect(viewerPage.locator('input[name="note"][value="A2"]')).toBeVisible({ timeout: 15000 });

        await actorContext.close();
        await viewerContext.close();
    });

    test('updates another viewer live after a roster-launched staff edit', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await loginAndOpenRoster(actorPage);
        await loginAndOpenRoster(viewerPage);

        const updatedName = 'Live';
        const actorEntry = managerEntry(actorPage);
        const viewerEntry = managerEntry(viewerPage);

        await expect(actorEntry).toBeVisible();
        await expect(viewerEntry).toBeVisible();

        await actorEntry.getByRole('button', { name: 'Edit' }).click();
        await expect(actorPage.locator('#dialog-overlay-mount [data-dialog-overlay="true"]')).toBeVisible();

        await actorPage.locator('#dialog-overlay-mount #firstName').fill('Live');
        await actorPage.locator('#dialog-overlay-mount #lastName').fill('Fragments');
        await actorPage.locator('#dialog-overlay-mount').getByRole('button', { name: 'Save' }).click();

        await expect(actorPage.locator('#dialog-overlay-mount')).toBeEmpty();
        await expect(
            actorPage.locator(`.roster-staff-panel-entry[data-roster-staff-name="${updatedName}"]`).first(),
        ).toBeVisible();
        await expect(
            viewerPage.locator(`.roster-staff-panel-entry[data-roster-staff-name="${updatedName}"]`).first(),
        ).toBeVisible();

        await actorContext.close();
        await viewerContext.close();
    });

    test('applies same-row staff assignment updates immediately even while the viewer is editing the note field', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await loginAndOpenRoster(actorPage);
        await normalizeLiveFragmentRoster(actorPage);
        await loginAndOpenRoster(viewerPage);

        const viewerRow = viewerPage.locator('tr[data-roster-row]').filter({ has: viewerPage.locator('select[name="staffId"]') }).first();
        const viewerStaffSelect = viewerRow.locator('select[name="staffId"]').first();
        const viewerNoteInput = viewerRow.locator('input[name="note"]').first();
        const actorStaffSelect = actorPage.locator('tr[data-roster-row]').filter({ has: actorPage.locator('select[name="staffId"]') }).first().locator('select[name="staffId"]').first();
        const managerStaffId = 'a0000000-0000-0000-0000-000000000101';

        await expect(viewerStaffSelect).toHaveValue('a1000000-0000-0000-0000-000000000031');

        await viewerNoteInput.click();
        await viewerNoteInput.fill('viewer keeps editing');
        await expect(viewerNoteInput).toBeFocused();

        await actorStaffSelect.selectOption(managerStaffId);

        await expect(managerEntry(actorPage)).toContainText('1');
        await expect(viewerStaffSelect).toHaveValue(managerStaffId);
        await expect(viewerNoteInput).toHaveValue('vi');
        await expectViewerRowAssignmentApplied(viewerPage);

        await actorContext.close();
        await viewerContext.close();
    });

    test('does not defer same-row live updates when a viewer has the staff select focused', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await loginAndOpenRoster(actorPage);
        await normalizeLiveFragmentRoster(actorPage);
        await loginAndOpenRoster(viewerPage);

        const viewerRow = viewerPage.locator('tr[data-roster-row]').filter({ has: viewerPage.locator('select[name="staffId"]') }).first();
        const viewerStaffSelect = viewerRow.locator('select[name="staffId"]').first();
        const actorStaffSelect = actorPage.locator('tr[data-roster-row]').filter({ has: actorPage.locator('select[name="staffId"]') }).first().locator('select[name="staffId"]').first();
        const managerStaffId = 'a0000000-0000-0000-0000-000000000101';

        await expect(viewerStaffSelect).toHaveValue('a1000000-0000-0000-0000-000000000031');

        await viewerStaffSelect.focus();
        await expect(viewerStaffSelect).toBeFocused();

        await actorStaffSelect.selectOption(managerStaffId);

        await expect(managerEntry(actorPage)).toContainText('1');
        await expect(viewerStaffSelect).toHaveValue(managerStaffId);
        await expectViewerRowAssignmentApplied(viewerPage);

        await actorContext.close();
        await viewerContext.close();
    });

    test('recovers from reconnect and reapplies the latest live roster state', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await loginAndOpenRoster(actorPage);
        await normalizeLiveFragmentRoster(actorPage);
        await loginAndOpenRoster(viewerPage);

        const viewerRow = viewerPage.locator('tr[data-roster-row]').filter({ has: viewerPage.locator('select[name="staffId"]') }).first();
        const viewerStaffSelect = viewerRow.locator('select[name="staffId"]').first();
        const viewerNoteInput = viewerRow.locator('input[name="note"]').first();
        const actorStaffSelect = actorPage.locator('tr[data-roster-row]').filter({ has: actorPage.locator('select[name="staffId"]') }).first().locator('select[name="staffId"]').first();
        const managerStaffId = 'a0000000-0000-0000-0000-000000000101';

        await expect(managerEntry(actorPage)).toContainText('0');
        await expect(managerEntry(viewerPage)).toContainText('0');
        await expect(viewerStaffSelect).toHaveValue('a1000000-0000-0000-0000-000000000031');

        await viewerContext.setOffline(true);
        await viewerNoteInput.click();
        await viewerNoteInput.fill('viewer reconnect edit');
        await expect(viewerNoteInput).toBeFocused();

        await actorStaffSelect.selectOption(managerStaffId);
        await expect(managerEntry(actorPage)).toContainText('1');

        await viewerContext.setOffline(false);

        await expect(managerEntry(viewerPage)).toContainText('1');
        await expectViewerRowAssignmentApplied(viewerPage);

        await actorContext.close();
        await viewerContext.close();
    });
});
