import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { openRoster } from './test-helpers';

async function loginAndOpenRoster(page) {
    await openRoster(page);
}

async function openRosterWeekOffset(page, weekOffset) {
    await openRoster(page, { weekOffset });
    await expect
        .poll(async () => {
            const rawConfig = await page.locator('#roster-week-shell').getAttribute('data-live-update-surface');
            if (!rawConfig) return null;
            return JSON.parse(rawConfig).scope?.weekOffset ?? null;
        })
        .toBe(weekOffset);
}

async function expectAutoCreatedDraftWeek(page) {
    await expect(page.locator('#roster-content')).toBeVisible();
    await expect(page.locator('[data-roster-row]')).toHaveCount(28);
    await expect(page.locator('.form-check-input[type="checkbox"]').first()).not.toBeChecked();
    await expect(page.getByRole('button', { name: 'Create Draft Roster' })).toHaveCount(0);
}

async function alternateStaffId(select) {
    const currentStaffId = await select.inputValue();
    const staffOptions = await select.evaluate((element) =>
        Array.from((element as HTMLSelectElement).options)
            .map((option) => option.value)
            .filter((value) => value.length > 0),
    );
    const firstStaffId = staffOptions[0] ?? '';
    return {
        initialStaffId: currentStaffId,
        nextStaffId: currentStaffId.length > 0 ? '' : firstStaffId,
    };
}

function staffSelects(page) {
    return page.locator('[data-roster-row]').filter({ has: page.locator('select[name="staffId"]') }).locator('select[name="staffId"]');
}

async function assignedStaffSelectCount(page) {
    return page.locator('select[name="staffId"]').evaluateAll((selects) =>
        selects.filter((select) => select instanceof HTMLSelectElement && select.value.length > 0).length,
    );
}

async function expectAssignedStaffSelectCount(page, count) {
    await expect.poll(() => assignedStaffSelectCount(page), { timeout: E2E_TIMEOUT.liveUpdate }).toBe(count);
}

async function pairedStaffSelects(actorPage, viewerPage) {
    const viewerStaffSelect = staffSelects(viewerPage).first();
    const fieldKey = await viewerStaffSelect.getAttribute('data-roster-field-key');
    expect(fieldKey).toBeTruthy();

    return {
        actorStaffSelect: actorPage.locator(`select[name="staffId"][data-roster-field-key="${fieldKey}"]`).first(),
        viewerStaffSelect,
    };
}

async function copyPreviousWeek(page) {
    page.once('dialog', (dialog) => dialog.accept());
    await page.getByRole('button', { name: 'Copy Previous Week' }).click();
    await expect(page.locator('#roster-week-shell')).toBeVisible();
}

test.describe('Roster live fragments', () => {
    test.setTimeout(E2E_TIMEOUT.slowTest);

    test('updates another viewer live after a slot assignment changes', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await loginAndOpenRoster(actorPage);
        await loginAndOpenRoster(viewerPage);

        const { actorStaffSelect: assignmentSelect, viewerStaffSelect: viewerAssignmentSelect } = await pairedStaffSelects(actorPage, viewerPage);
        const { initialStaffId, nextStaffId } = await alternateStaffId(viewerAssignmentSelect);

        await expect(assignmentSelect).toHaveValue(initialStaffId);

        await assignmentSelect.selectOption(nextStaffId);

        await expect(assignmentSelect).toHaveValue(nextStaffId);
        await expect(viewerAssignmentSelect).toHaveValue(nextStaffId);

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
        await expectAssignedStaffSelectCount(viewerPage, 0);

        await copyPreviousWeek(actorPage);

        await expectAssignedStaffSelectCount(actorPage, 2);
        await expectAssignedStaffSelectCount(viewerPage, 2);

        await actorContext.close();
        await viewerContext.close();
    });

    test('does not defer same-row live updates when a viewer has the staff select focused', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await loginAndOpenRoster(actorPage);
        await loginAndOpenRoster(viewerPage);

        const { actorStaffSelect, viewerStaffSelect } = await pairedStaffSelects(actorPage, viewerPage);
        const { nextStaffId } = await alternateStaffId(viewerStaffSelect);

        await viewerStaffSelect.focus();
        await expect(viewerStaffSelect).toBeFocused();

        await actorStaffSelect.selectOption(nextStaffId);

        await expect(actorStaffSelect).toHaveValue(nextStaffId);
        await expect(viewerStaffSelect).toHaveValue(nextStaffId);

        await actorContext.close();
        await viewerContext.close();
    });

    test('recovers from reconnect and reapplies the latest live roster state', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await loginAndOpenRoster(actorPage);
        await loginAndOpenRoster(viewerPage);

        const { actorStaffSelect, viewerStaffSelect } = await pairedStaffSelects(actorPage, viewerPage);
        const { nextStaffId } = await alternateStaffId(viewerStaffSelect);

        await viewerContext.setOffline(true);

        await actorStaffSelect.selectOption(nextStaffId);
        await expect(actorStaffSelect).toHaveValue(nextStaffId);

        await viewerContext.setOffline(false);

        await expect(viewerStaffSelect).toHaveValue(nextStaffId);

        await actorContext.close();
        await viewerContext.close();
    });
});
