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

async function openRosterWeekOffset(page, weekOffset) {
    await loginAndOpenRoster(page);

    for (let step = 0; step < weekOffset; step += 1) {
        await page.getByRole('link', { name: '>' }).click();
        await expect(page.locator('#roster-week-shell')).toHaveAttribute(
            'data-live-update-week-offset',
            String(step + 1),
        );
    }

    await expect(page.locator('#roster-week-shell')).toHaveAttribute(
        'data-live-update-week-offset',
        String(weekOffset),
    );
}

async function ensureDraftWeek(page, actionName) {
    const content = page.locator('#roster-content');
    await expect(content).toBeVisible();
    await expect(page.locator('tr[data-roster-row]')).toHaveCount(28);
    await expect(page.locator('.form-check-input[type="checkbox"]').first()).not.toBeChecked();
}

async function selectStaffForRow(page, rowIndex, staffId) {
    const row = page.locator('tr[data-roster-row]').filter({ has: page.locator('select[name="staffId"]') }).nth(rowIndex);
    const select = row.locator('select[name="staffId"]');
    await select.selectOption(staffId);
    await expect(select).toHaveValue(staffId);
}

function managerEntry(page) {
    return page
        .locator('#roster-staff-panel-fragment .roster-staff-panel-entry')
        .filter({ hasText: /E2E Manager|Live Fragments/ })
        .first();
}

function firstViewerRow(page) {
    return page.locator('tbody[data-roster-day-section="true"]').first().locator('tr[data-roster-row]').first();
}

async function expectViewerRowAssignmentApplied(page) {
    await expect(firstViewerRow(page)).toContainText(/Manager, E2E|Fragments, Live/, { timeout: 15000 });
}

async function normalizeLiveFragmentRoster(page) {
    const alphaCrewStaffId = 'a1000000-0000-0000-0000-000000000031';
    const managerPanelEntry = managerEntry(page);
    const editableRows = page.locator('tr[data-roster-row]').filter({ has: page.locator('select[name="staffId"]') });
    const rowCount = await editableRows.count();

    await selectStaffForRow(page, 0, alphaCrewStaffId);

    for (let rowIndex = 1; rowIndex < rowCount; rowIndex += 1) {
        await selectStaffForRow(page, rowIndex, '');
    }

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

        const assignmentSelect = actorPage.locator('select[name="staffId"]').first();
        await assignmentSelect.selectOption('a0000000-0000-0000-0000-000000000101');

        await expect(actorManagerEntry).toContainText('1');
        await expect(viewerManagerEntry).toContainText('1');

        await actorContext.close();
        await viewerContext.close();
    });

    test('updates another manager live after creating a draft week from an empty page', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await openRosterWeekOffset(actorPage, 2);
        await openRosterWeekOffset(viewerPage, 2);

        await ensureDraftWeek(actorPage, 'Create Draft Roster');
        await expect(viewerPage.locator('tr[data-roster-row]')).toHaveCount(28);
        await expect(viewerPage.locator('.form-check-input[type="checkbox"]').first()).not.toBeChecked();

        await actorContext.close();
        await viewerContext.close();
    });

    test('updates another manager live after copying the previous week into an empty page', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await openRosterWeekOffset(actorPage, 1);
        await openRosterWeekOffset(viewerPage, 1);

        await ensureDraftWeek(actorPage, 'Copy Previous Week');
        await expect(viewerPage.locator('tr[data-roster-row]')).toHaveCount(28);
        await expect(viewerPage.locator('.form-check-input[type="checkbox"]').first()).not.toBeChecked();

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

        const updatedName = 'Live Fragments';
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
            actorPage.locator('.roster-staff-panel-entry').filter({ hasText: updatedName }).first(),
        ).toBeVisible();
        await expect(
            viewerPage.locator('.roster-staff-panel-entry').filter({ hasText: updatedName }).first(),
        ).toBeVisible();

        await actorContext.close();
        await viewerContext.close();
    });

    test('defers same-row live updates for a viewer until the focused input blurs', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await loginAndOpenRoster(actorPage);
        await normalizeLiveFragmentRoster(actorPage);
        await loginAndOpenRoster(viewerPage);

        const viewerRow = viewerPage.locator('tr[data-roster-row]').filter({ has: viewerPage.locator('select[name="staffId"]') }).first();
        const viewerStaffSelect = viewerRow.locator('select[name="staffId"]');
        const viewerNoteInput = viewerRow.locator('input[name="note"]');
        const actorStaffSelect = actorPage.locator('select[name="staffId"]').first();
        const managerStaffId = 'a0000000-0000-0000-0000-000000000101';

        await expect(viewerStaffSelect).toHaveValue('a1000000-0000-0000-0000-000000000031');

        await viewerNoteInput.click();
        await viewerNoteInput.fill('viewer keeps editing');
        await expect(viewerNoteInput).toBeFocused();

        await actorStaffSelect.selectOption(managerStaffId);

        await expect(managerEntry(actorPage)).toContainText('1');
        await expect(viewerStaffSelect).toHaveValue('a1000000-0000-0000-0000-000000000031');

        await viewerPage.locator('h1').click();
        await expectViewerRowAssignmentApplied(viewerPage);

        await actorContext.close();
        await viewerContext.close();
    });

    test.fixme('recovers from reconnect and reapplies the latest live roster state', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await loginAndOpenRoster(actorPage);
        await normalizeLiveFragmentRoster(actorPage);
        await loginAndOpenRoster(viewerPage);

        const viewerRow = viewerPage.locator('tr[data-roster-row]').filter({ has: viewerPage.locator('select[name="staffId"]') }).first();
        const viewerStaffSelect = viewerRow.locator('select[name="staffId"]');
        const viewerNoteInput = viewerRow.locator('input[name="note"]');
        const actorStaffSelect = actorPage.locator('select[name="staffId"]').first();
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
