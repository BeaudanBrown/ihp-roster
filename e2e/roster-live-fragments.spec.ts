import { test, expect, type Page, type Locator } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { openRoster } from './test-helpers';

async function loginAndOpenRoster(page: Page) {
    await openRoster(page);
}

async function openRosterWeekOffset(page: Page, weekOffset: number) {
    await openRoster(page, { weekOffset });
    await expect
        .poll(async () => {
            const rawConfig = await page.locator('#roster-week-shell').getAttribute('data-live-update-surface');
            if (!rawConfig) return null;
            return JSON.parse(rawConfig).scope?.weekOffset ?? null;
        })
        .toBe(weekOffset);
}

async function expectAutoCreatedDraftWeek(page: Page) {
    await expect(page.locator('#roster-content')).toBeVisible();
    await expect(page.locator('[data-roster-row]')).toHaveCount(28);
    await expect(page.locator('[data-app-toggle-button-input="true"][role="switch"]').first()).not.toBeChecked();
    await expect(page.getByRole('button', { name: 'Create Draft Roster' })).toHaveCount(0);
}

function existingShiftLaunchers(page: Page): Locator {
    return page.locator('[data-roster-shift-launcher="true"][data-roster-slot-id]:not([data-roster-slot-id=""])');
}

async function firstExistingShiftGroupKey(page: Page): Promise<string> {
    const launcher = existingShiftLaunchers(page).first();
    await expect(launcher).toBeVisible();
    const groupKey = await launcher.getAttribute('data-roster-shift-group-key');
    expect(groupKey).toBeTruthy();
    return groupKey ?? '';
}

function shiftGroupLaunchers(page: Page, groupKey: string): Locator {
    return page.locator(`[data-roster-shift-group-key="${groupKey}"][data-roster-shift-launcher="true"]`);
}

async function shiftGroupStaffId(page: Page, groupKey: string): Promise<string> {
    return (await shiftGroupLaunchers(page, groupKey).first().getAttribute('data-roster-staff-id')) ?? '';
}

async function changeShiftToAlternateStaff(page: Page, groupKey: string): Promise<string> {
    const launcher = page.locator(`[data-roster-shift-group-key="${groupKey}"][hx-get*="EditRosterSlotDialog"]`).first();
    await expect(launcher).toBeVisible();
    await launcher.scrollIntoViewIfNeeded();
    const dialogResponsePromise = page.waitForResponse((response) =>
        response.request().method() === 'GET' && response.url().includes('/EditRosterSlotDialog')
    );
    await launcher.click({ force: true });
    const dialogResponse = await dialogResponsePromise;
    expect(dialogResponse.status(), await dialogResponse.text()).toBe(200);
    const dialog = page.locator('#dialog-overlay-mount [data-dialog-overlay="true"]');
    await expect(dialog).toBeVisible();

    const staffSelect = page.locator('#roster-shift-staff-id');
    const currentStaffId = await staffSelect.inputValue();
    const nextStaffId = await staffSelect.evaluate((element, current) => {
        const select = element as HTMLSelectElement;
        return Array.from(select.options)
            .map((option) => option.value)
            .find((value) => value.length > 0 && value !== current) ?? '';
    }, currentStaffId);
    expect(nextStaffId).not.toBe('');

    await staffSelect.selectOption(nextStaffId);
    const updateResponsePromise = page.waitForResponse((response) =>
        response.request().method() === 'POST' && response.url().includes('/UpdateRosterSlot')
    );
    await page.getByRole('button', { name: 'Save' }).click();
    const updateResponse = await updateResponsePromise;
    expect(updateResponse.status(), await updateResponse.text()).toBe(200);
    await expect(dialog).toHaveCount(0);
    return nextStaffId;
}

async function assignedShiftCount(page: Page): Promise<number> {
    return page.locator('[data-roster-shift-group-key^="existing:"][data-roster-staff-id]:not([data-roster-staff-id=""])').evaluateAll((elements) => {
        return new Set(elements.map((element) => (element as HTMLElement).dataset.rosterShiftGroupKey ?? '')).size;
    });
}

async function expectAssignedShiftCount(page: Page, count: number) {
    await expect.poll(() => assignedShiftCount(page), { timeout: E2E_TIMEOUT.liveUpdate }).toBe(count);
}

async function expectShiftGroupStaffId(page: Page, groupKey: string, staffId: string) {
    await expect.poll(() => shiftGroupStaffId(page, groupKey), { timeout: E2E_TIMEOUT.liveUpdate }).toBe(staffId);
}

async function copyPreviousWeek(page: Page) {
    const copyButton = page.getByRole('button', { name: 'Copy Previous Week' });
    if (!(await copyButton.isVisible().catch(() => false))) {
        await page.getByRole('button', { name: 'Roster settings' }).click();
        await expect(copyButton).toBeVisible();
    }
    page.once('dialog', (dialog) => dialog.accept());
    await copyButton.click();
    await expect(page.locator('#roster-week-shell')).toBeVisible();
}

test.describe('Roster live fragments', () => {
    test.setTimeout(E2E_TIMEOUT.slowTest);

    test('updates another viewer live after a shift assignment changes', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await loginAndOpenRoster(actorPage);
        await loginAndOpenRoster(viewerPage);

        const groupKey = await firstExistingShiftGroupKey(viewerPage);
        const initialStaffId = await shiftGroupStaffId(viewerPage, groupKey);
        await expectShiftGroupStaffId(actorPage, groupKey, initialStaffId);

        const nextStaffId = await changeShiftToAlternateStaff(actorPage, groupKey);

        await expectShiftGroupStaffId(actorPage, groupKey, nextStaffId);
        await expectShiftGroupStaffId(viewerPage, groupKey, nextStaffId);

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
        await expectAssignedShiftCount(viewerPage, 0);

        await copyPreviousWeek(actorPage);

        await expectAssignedShiftCount(actorPage, 2);
        await expectAssignedShiftCount(viewerPage, 2);

        await actorContext.close();
        await viewerContext.close();
    });

    test('does not defer same-row live updates when a viewer has a shift launcher focused', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await loginAndOpenRoster(actorPage);
        await loginAndOpenRoster(viewerPage);

        const groupKey = await firstExistingShiftGroupKey(viewerPage);
        const viewerLauncher = shiftGroupLaunchers(viewerPage, groupKey).first();
        await viewerLauncher.focus();
        await expect(viewerLauncher).toBeFocused();

        const nextStaffId = await changeShiftToAlternateStaff(actorPage, groupKey);

        await expectShiftGroupStaffId(actorPage, groupKey, nextStaffId);
        await expectShiftGroupStaffId(viewerPage, groupKey, nextStaffId);

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

        const groupKey = await firstExistingShiftGroupKey(viewerPage);
        await viewerContext.setOffline(true);

        const nextStaffId = await changeShiftToAlternateStaff(actorPage, groupKey);
        await expectShiftGroupStaffId(actorPage, groupKey, nextStaffId);

        await viewerContext.setOffline(false);

        await expectShiftGroupStaffId(viewerPage, groupKey, nextStaffId);

        await actorContext.close();
        await viewerContext.close();
    });
});
