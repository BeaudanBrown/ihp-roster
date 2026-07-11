import { test, expect, type Page, type Locator } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { ensureRosterLayout, fillRosterShiftDialogDefaults, openRoster, openRosterShiftDialog, saveRosterShiftDialog } from './test-helpers';

async function loginAndOpenRoster(page: Page) {
    await openRoster(page);
}

async function openDayColumnsRoster(page: Page) {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await openRoster(page);
    await ensureRosterLayout(page, 'day_columns');
    await expect(page.locator('#roster-grid-frame')).toBeVisible();
    await expect(page.locator('#roster-day-columns')).toBeVisible();
}

async function markRosterScrollOwner(page: Page, marker: string): Promise<number> {
    return page.locator('#roster-grid-frame').evaluate((element, markerValue) => {
        if (!(element instanceof HTMLElement)) throw new Error('Expected roster grid frame');
        const maxScrollLeft = Math.max(0, element.scrollWidth - element.clientWidth);
        element.scrollLeft = maxScrollLeft > 0 ? Math.min(Math.max(90, element.clientWidth * 0.8), maxScrollLeft) : 0;
        element.dataset.e2eScrollOwnerMarker = markerValue;
        return element.scrollLeft;
    }, marker);
}

async function expectRosterScrollOwnerPreserved(page: Page, marker: string, expectedScrollLeft: number) {
    await expect(page.locator('#roster-grid-frame')).toHaveAttribute('data-e2e-scroll-owner-marker', marker);
    if (expectedScrollLeft > 0) {
        await expect.poll(() => page.locator('#roster-grid-frame').evaluate((element, expected) => {
            if (!(element instanceof HTMLElement)) throw new Error('Expected roster grid frame');
            return Math.abs(element.scrollLeft - expected);
        }, expectedScrollLeft)).toBeLessThanOrEqual(2);
    }
}

async function openRosterWeekOffset(page: Page, weekOffset: number) {
    await openRoster(page, { weekOffset });
    await expect
        .poll(async () => {
            const rawConfig = await page.locator('[data-bepis-surface-config]').first().getAttribute('data-bepis-surface-config');
            if (!rawConfig) return null;
            const scopeKey = JSON.parse(rawConfig).scopeKey;
            if (typeof scopeKey !== 'string') return null;
            const parts = scopeKey.split(':');
            return Number(parts[parts.length - 1]);
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
    await openRosterShiftDialog(page, launcher);

    const staffSelect = page.locator('#roster-shift-staff-id');
    const currentStaffId = await staffSelect.inputValue();
    const nextStaffId = await staffSelect.evaluate((element, current) => {
        const select = element as HTMLSelectElement;
        return Array.from(select.options)
            .map((option) => option.value)
            .find((value) => value.length > 0 && value !== current) ?? '';
    }, currentStaffId);
    expect(nextStaffId).not.toBe('');

    await fillRosterShiftDialogDefaults(page);
    await staffSelect.selectOption(nextStaffId);
    await saveRosterShiftDialog(page);
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
        await viewerPage.reload();
        await expect(viewerPage.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await expectShiftGroupStaffId(viewerPage, groupKey, nextStaffId);

        await actorContext.close();
        await viewerContext.close();
    });

    test('preserves day-column scroll owners for actor and passive shift live refreshes', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await openDayColumnsRoster(actorPage);
        await openDayColumnsRoster(viewerPage);

        const actorScroll = await markRosterScrollOwner(actorPage, 'actor-scroll-owner');
        const viewerScroll = await markRosterScrollOwner(viewerPage, 'viewer-scroll-owner');
        const groupKey = await firstExistingShiftGroupKey(viewerPage);

        await changeShiftToAlternateStaff(actorPage, groupKey);

        await expectRosterScrollOwnerPreserved(actorPage, 'actor-scroll-owner', actorScroll);
        await expectRosterScrollOwnerPreserved(viewerPage, 'viewer-scroll-owner', viewerScroll);

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
        await viewerPage.reload();
        await expect(viewerPage.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
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
        await viewerPage.reload();
        await expect(viewerPage.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
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
        await viewerPage.reload();
        await expect(viewerPage.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });

        await expectShiftGroupStaffId(viewerPage, groupKey, nextStaffId);

        await actorContext.close();
        await viewerContext.close();
    });
});
