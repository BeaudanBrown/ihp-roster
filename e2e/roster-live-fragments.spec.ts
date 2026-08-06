import { test, expect, type Page, type Locator } from '@playwright/test';
import {
    rosterShiftGroupHighlightMemberDomAttr,
    rosterStaffHighlightMemberDomAttr,
    toggleInputDomAttr,
    toggleRootDomAttr,
} from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from './timeouts';
import { ensureRosterLayout, fillRosterShiftDialogDefaults, openRoster, openRosterSettings, openRosterShiftDialog, runSql, saveRosterShiftDialog } from './test-helpers';

type OpenShiftLiveWindow = Window & { __openShiftRosterSubscriptions?: string[] };

async function installOpenShiftLiveObserver(page: Page) {
    await page.addInitScript(() => {
        const state = window as OpenShiftLiveWindow;
        state.__openShiftRosterSubscriptions = [];
        document.addEventListener('app:live-update-debug', (event) => {
            const detail = (event as CustomEvent).detail;
            if (detail?.name === 'subscription_added' && typeof detail.scopeKey === 'string') {
                state.__openShiftRosterSubscriptions?.push(detail.scopeKey);
            }
        });
    });
}

async function waitForOpenShiftRosterSubscription(page: Page) {
    await expect.poll(
        () => page.evaluate(() =>
            (window as OpenShiftLiveWindow).__openShiftRosterSubscriptions?.some((scopeKey) => scopeKey.startsWith('roster:')) ?? false,
        ),
        { timeout: E2E_TIMEOUT.liveUpdate },
    ).toBe(true);
}

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

async function markRosterScrollOwner(page: Page, marker: string, selector = '#roster-grid-frame'): Promise<number> {
    return page.locator(selector).evaluate((element, markerValue) => {
        if (!(element instanceof HTMLElement)) throw new Error('Expected roster scroll owner');
        const maxScrollLeft = Math.max(0, element.scrollWidth - element.clientWidth);
        element.scrollLeft = maxScrollLeft > 0 ? Math.min(Math.max(90, element.clientWidth * 0.8), maxScrollLeft) : 0;
        element.dataset.e2eScrollOwnerMarker = markerValue;
        return element.scrollLeft;
    }, marker);
}

async function expectRosterScrollOwnerPreserved(page: Page, marker: string, expectedScrollLeft: number, selector = '#roster-grid-frame') {
    await expect(page.locator(selector)).toHaveAttribute('data-e2e-scroll-owner-marker', marker);
    if (expectedScrollLeft > 0) {
        await expect.poll(() => page.locator(selector).evaluate((element, expected) => {
            if (!(element instanceof HTMLElement)) throw new Error('Expected roster scroll owner');
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
    await expect(page.locator(`[${toggleInputDomAttr}][role="switch"]`).first()).not.toBeChecked();
    await expect(page.getByRole('button', { name: 'Create Draft Roster' })).toHaveCount(0);
}

function existingShiftLaunchers(page: Page): Locator {
    return page.locator('[data-roster-shift-launcher="true"][hx-get*="EditRosterSlotDialog"]');
}

async function firstExistingShiftGroupKey(page: Page): Promise<string> {
    const launcher = existingShiftLaunchers(page).first();
    await expect(launcher).toBeVisible();
    const groupKey = await launcher.getAttribute(rosterShiftGroupHighlightMemberDomAttr);
    expect(groupKey).toBeTruthy();
    return groupKey ?? '';
}

function shiftGroupLaunchers(page: Page, groupKey: string): Locator {
    return page.locator(`[${rosterShiftGroupHighlightMemberDomAttr}="${groupKey}"][data-roster-shift-launcher="true"]`);
}

async function shiftGroupStaffKey(page: Page, groupKey: string): Promise<string> {
    return await shiftGroupLaunchers(page, groupKey).first().getAttribute(rosterStaffHighlightMemberDomAttr) ?? '';
}

async function changeShiftToAlternateStaffKey(page: Page, groupKey: string): Promise<string> {
    const previousStaffKey = await shiftGroupStaffKey(page, groupKey);
    const launcher = page.locator(`[${rosterShiftGroupHighlightMemberDomAttr}="${groupKey}"][hx-get*="EditRosterSlotDialog"]`).first();
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
    await expect
        .poll(() => shiftGroupStaffKey(page, groupKey), { timeout: E2E_TIMEOUT.liveUpdate })
        .not.toBe(previousStaffKey);
    return await shiftGroupStaffKey(page, groupKey);
}

async function assignedShiftCount(page: Page): Promise<number> {
    return page
        .locator(`[hx-get*="EditRosterSlotDialog"][${rosterShiftGroupHighlightMemberDomAttr}][${rosterStaffHighlightMemberDomAttr}]`)
        .evaluateAll((elements, groupAttr) => {
            return new Set(elements.map((element) => element.getAttribute(groupAttr) ?? '')).size;
        }, rosterShiftGroupHighlightMemberDomAttr);
}

async function expectAssignedShiftCount(page: Page, count: number) {
    await expect.poll(() => assignedShiftCount(page), { timeout: E2E_TIMEOUT.liveUpdate }).toBe(count);
}

async function expectShiftGroupStaffKey(page: Page, groupKey: string, staffKey: string) {
    await expect.poll(() => shiftGroupStaffKey(page, groupKey), { timeout: E2E_TIMEOUT.liveUpdate }).toBe(staffKey);
}

async function copyPreviousWeek(page: Page) {
    const copyButton = page.getByRole('button', { name: 'Copy Previous Week' });
    if (!(await copyButton.isVisible().catch(() => false))) {
        await openRosterSettings(page);
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
        const initialStaffKey = await shiftGroupStaffKey(viewerPage, groupKey);
        await expectShiftGroupStaffKey(actorPage, groupKey, initialStaffKey);

        const nextStaffKey = await changeShiftToAlternateStaffKey(actorPage, groupKey);

        await expectShiftGroupStaffKey(actorPage, groupKey, nextStaffKey);
        await viewerPage.reload();
        await expect(viewerPage.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await expectShiftGroupStaffKey(viewerPage, groupKey, nextStaffKey);

        await actorContext.close();
        await viewerContext.close();
    });

    test('publishes and fills an Open shift with role-safe passive live updates', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const managerViewerContext = await browser.newContext();
        const workerViewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const managerViewerPage = await managerViewerContext.newPage();
        const workerViewerPage = await workerViewerContext.newPage();
        const weekOffset = 21;

        await openRosterWeekOffset(actorPage, weekOffset);
        const createLauncher = actorPage.locator('[data-roster-shift-launcher="true"][hx-get*="NewRosterSlotDialog"]').first();
        await openRosterShiftDialog(actorPage, createLauncher);
        await actorPage.locator('#roster-shift-staff-id').selectOption('open');
        await fillRosterShiftDialogDefaults(actorPage);
        await saveRosterShiftDialog(actorPage);

        const actorOpenLauncher = actorPage.locator('.is-roster-shift-open[data-roster-shift-launcher="true"][hx-get*="EditRosterSlotDialog"]').first();
        await expect(actorOpenLauncher).toContainText('OPEN');

        const liveToggle = actorPage
            .locator('[data-week-toolbar="roster"]')
            .locator(`[${toggleRootDomAttr}]`)
            .filter({ hasText: 'Live' });
        const publishResponse = actorPage.waitForResponse((response) =>
            response.request().method() === 'POST' && new URL(response.url()).pathname.includes('ToggleRosterWeekLiveStatus'),
        );
        await liveToggle.click();
        expect((await publishResponse).ok()).toBe(true);
        await expect(liveToggle.locator(`[${toggleInputDomAttr}]`)).toBeChecked({ timeout: E2E_TIMEOUT.liveUpdate });
        await expect(actorOpenLauncher).not.toHaveAttribute('data-bepis-source-ref', /.+/);

        await Promise.all([
            installOpenShiftLiveObserver(managerViewerPage),
            installOpenShiftLiveObserver(workerViewerPage),
        ]);
        await Promise.all([
            openRoster(managerViewerPage, { weekOffset, ensureDraft: false, ensureEditable: false }),
            openRoster(workerViewerPage, { email: 'e2e-worker@example.com', weekOffset, ensureDraft: false, ensureEditable: false }),
        ]);
        await Promise.all([
            waitForOpenShiftRosterSubscription(managerViewerPage),
            waitForOpenShiftRosterSubscription(workerViewerPage),
        ]);

        const managerOpenLauncher = managerViewerPage.locator('.is-roster-shift-open[data-roster-shift-launcher="true"][hx-get*="EditRosterSlotDialog"]').first();
        await expect(managerOpenLauncher).toContainText('OPEN');
        await expect(workerViewerPage.getByText('OPEN', { exact: true }).first()).toBeVisible();
        await expect(workerViewerPage.locator('.is-roster-shift-open[hx-get*="EditRosterSlotDialog"]')).toHaveCount(0);

        await openRosterShiftDialog(actorPage, actorOpenLauncher);
        await expect(actorPage.locator('[data-roster-live-open-fill="true"]')).toBeVisible();
        const protectedFields = actorPage.locator('[data-roster-live-open-fields="true"]');
        await expect(protectedFields).toHaveCount(2);
        await expect(protectedFields.first()).toHaveAttribute('disabled', /.*/);
        await expect(actorPage.locator('#roster-shift-type-id')).toBeDisabled();
        const staffSelect = actorPage.locator('#roster-shift-staff-id');
        const fillOption = await staffSelect.locator('option').evaluateAll((options) =>
            options
                .map((option) => option instanceof HTMLOptionElement ? { value: option.value, label: option.textContent?.trim() ?? '' } : { value: '', label: '' })
                .find((option) => option.value !== '' && option.value !== 'open') ?? { value: '', label: '' },
        );
        expect(fillOption.value).not.toBe('');
        await staffSelect.selectOption(fillOption.value);
        await saveRosterShiftDialog(actorPage);

        await expect(actorPage.locator('.is-roster-shift-open')).toHaveCount(0, { timeout: E2E_TIMEOUT.liveUpdate });
        await expect(managerViewerPage.locator('.is-roster-shift-open')).toHaveCount(0, { timeout: E2E_TIMEOUT.liveUpdate });
        await expect(workerViewerPage.locator('.is-roster-shift-open')).toHaveCount(0, { timeout: E2E_TIMEOUT.liveUpdate });
        await expect(managerViewerPage.getByText(fillOption.label, { exact: true }).first()).toBeVisible();
        await expect(workerViewerPage.getByText(fillOption.label, { exact: true }).first()).toBeVisible();

        await actorContext.close();
        await managerViewerContext.close();
        await workerViewerContext.close();
    });

    test('preserves day-column and day-row scroll owners for actor and passive shift live refreshes', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await openDayColumnsRoster(actorPage);
        await openDayColumnsRoster(viewerPage);

        const actorScroll = await markRosterScrollOwner(actorPage, 'actor-scroll-owner');
        const viewerScroll = await markRosterScrollOwner(viewerPage, 'viewer-scroll-owner');
        const groupKey = await firstExistingShiftGroupKey(viewerPage);

        await changeShiftToAlternateStaffKey(actorPage, groupKey);

        await expectRosterScrollOwnerPreserved(actorPage, 'actor-scroll-owner', actorScroll);
        await expectRosterScrollOwnerPreserved(viewerPage, 'viewer-scroll-owner', viewerScroll);

        await ensureRosterLayout(actorPage, 'day_rows');
        await ensureRosterLayout(viewerPage, 'day_rows');
        await expect(actorPage.locator('.roster-slots-scroller')).toBeVisible();
        await expect(viewerPage.locator('.roster-slots-scroller')).toBeVisible();
        const actorDayRowsScroll = await markRosterScrollOwner(actorPage, 'actor-day-rows-scroll-owner', '.roster-slots-scroller');
        const viewerDayRowsScroll = await markRosterScrollOwner(viewerPage, 'viewer-day-rows-scroll-owner', '.roster-slots-scroller');
        const dayRowsGroupKey = await firstExistingShiftGroupKey(viewerPage);

        await changeShiftToAlternateStaffKey(actorPage, dayRowsGroupKey);

        await expectRosterScrollOwnerPreserved(actorPage, 'actor-day-rows-scroll-owner', actorDayRowsScroll, '.roster-slots-scroller');
        await expectRosterScrollOwnerPreserved(viewerPage, 'viewer-day-rows-scroll-owner', viewerDayRowsScroll, '.roster-slots-scroller');

        await actorContext.close();
        await viewerContext.close();
    });

    test('auto-creates a future draft week on navigation without exposing a separate create action', async ({ page }) => {
        await openRosterWeekOffset(page, 2);
        await expectAutoCreatedDraftWeek(page);
    });

    test('updates another manager live after copying the previous week into an auto-created draft week', async ({ browser }) => {
        runSql(`
            UPDATE roster_slots
            SET deleted_at = NOW(),
                deleted_by_user_id = 'a0000000-0000-0000-0000-000000000003',
                delete_reason = 'E2E copy-previous reset',
                updated_at = NOW()
            WHERE roster_day_id IN (
                SELECT roster_days.id
                FROM roster_days
                JOIN roster_weeks ON roster_weeks.id = roster_days.roster_week_id
                WHERE roster_weeks.venue_id = 'a1000000-0000-0000-0000-000000000001'
                  AND roster_weeks.roster_group_id = 'a1000000-0000-0000-0000-000000000211'
                  AND roster_weeks.week_offset = 2
            ) AND deleted_at IS NULL;
            UPDATE roster_week_slot_definitions
            SET deleted_at = NULL, updated_at = NOW()
            WHERE id = 'a1000000-0000-0000-0000-000000000083';
            UPDATE roster_slots
            SET assignment_state = 'staff',
                staff_id = 'a1000000-0000-0000-0000-000000000031',
                deleted_at = NULL,
                deleted_by_user_id = NULL,
                delete_reason = NULL,
                updated_at = NOW()
            WHERE id IN (
                'a1000000-0000-0000-0000-000000000073',
                'a1000000-0000-0000-0000-000000000074'
            );
        `);
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

        const nextStaffKey = await changeShiftToAlternateStaffKey(actorPage, groupKey);

        await expectShiftGroupStaffKey(actorPage, groupKey, nextStaffKey);
        await viewerPage.reload();
        await expect(viewerPage.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await expectShiftGroupStaffKey(viewerPage, groupKey, nextStaffKey);

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

        const nextStaffKey = await changeShiftToAlternateStaffKey(actorPage, groupKey);
        await expectShiftGroupStaffKey(actorPage, groupKey, nextStaffKey);

        await viewerContext.setOffline(false);
        await viewerPage.reload();
        await expect(viewerPage.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });

        await expectShiftGroupStaffKey(viewerPage, groupKey, nextStaffKey);

        await actorContext.close();
        await viewerContext.close();
    });
});
