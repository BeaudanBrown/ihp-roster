import { test, expect, Page } from '@playwright/test';
import {
    liveFragmentsRefreshEvent,
    rosterStaffHighlightDefaultDomAttr,
    rosterStaffHighlightMemberDomAttr,
    rosterStaffHighlightOrderDomAttr,
    rosterStaffHighlightPinDomAttr,
    rosterStaffHighlightSourceDomAttr,
    rosterStaffPanelSortRowDomAttr,
    rosterWageFilterConfigDomAttr,
    toggleInputDomAttr,
    toggleRootDomAttr,
} from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT, ensureRosterLayout, gotoWhenReady, loginAsPrivilegedUserWithSeededPasskeySession, openRoster, runSql } from './test-helpers';

type GridSlotMetrics = {
    slotCellCount: number;
    highlightedCount: number;
    startCount: number;
    endCount: number;
    lastBorderRightWidth: string;
    lastBoxShadow: string;
    lastControlLeft: number | null;
    lastControlWidth: number | null;
};

async function firstAssignedStaffKey(page: Page) {
    const assignedLauncher = page
        .locator(`[data-roster-shift-launcher="true"][${rosterStaffHighlightMemberDomAttr}]`)
        .first();
    await expect(assignedLauncher).toBeVisible();
    return (await assignedLauncher.getAttribute(rosterStaffHighlightMemberDomAttr)) ?? '';
}

async function chooseRosterLayout(page: Page, layoutMode: 'day_rows' | 'day_columns') {
    await ensureRosterLayout(page, layoutMode);
}

async function hoverStaffRow(page: Page, staffKey: string) {
    const staffRow = page.locator(`[${rosterStaffPanelSortRowDomAttr}][${rosterStaffHighlightSourceDomAttr}="${staffKey}"]`).first();
    await expect(staffRow).toBeVisible();
    await staffRow.hover();
    await expect(staffRow).toHaveClass(/is-linked-highlight-source/);
}

async function toggleLocateShifts(page: Page, staffKey: string) {
    const staffRow = page.locator(`[${rosterStaffPanelSortRowDomAttr}][${rosterStaffHighlightSourceDomAttr}="${staffKey}"]`).first();
    await expect(staffRow).toBeVisible();

    const locateButton = staffRow.locator(`[${rosterStaffHighlightPinDomAttr}="${staffKey}"]`);
    await staffRow.hover();
    await expect(locateButton).toBeVisible();
    await locateButton.evaluate((button) => {
        if (!(button instanceof HTMLElement)) throw new Error('Expected locate button');
        button.click();
    });
    await expect(locateButton).toHaveAttribute('aria-pressed', 'true');
}

async function gridSlotMetrics(page: Page, staffKey: string): Promise<GridSlotMetrics> {
    return await page.evaluate(({ targetStaffKey, memberAttr, orderAttr }) => {
        const staffCells = Array.from(
            document.querySelectorAll<HTMLElement>(`.roster-grid [role="gridcell"][${memberAttr}][${orderAttr}]`),
        ).filter((cell) => cell.getAttribute(memberAttr) === targetStaffKey);
        const orderKey = staffCells[0]?.getAttribute(orderAttr) ?? '';
        const slotCells = staffCells.filter((cell) => cell.getAttribute(orderAttr) === orderKey);
        const lastCell = slotCells[slotCells.length - 1] ?? null;
        const lastControl = lastCell?.querySelector<HTMLElement>('.slot-cell-static') ?? null;
        const lastControlRect = lastControl?.getBoundingClientRect();

        return {
            slotCellCount: slotCells.length,
            highlightedCount: slotCells.filter((cell) => cell.classList.contains('is-linked-highlight-member')).length,
            startCount: slotCells.filter((cell) => cell.classList.contains('is-linked-highlight-member-first')).length,
            endCount: slotCells.filter((cell) => cell.classList.contains('is-linked-highlight-member-last')).length,
            lastBorderRightWidth: lastCell ? getComputedStyle(lastCell).borderRightWidth : '',
            lastBoxShadow: lastCell ? getComputedStyle(lastCell).boxShadow : '',
            lastControlLeft: lastControlRect?.left ?? null,
            lastControlWidth: lastControlRect?.width ?? null,
        };
    }, {
        targetStaffKey: staffKey,
        memberAttr: rosterStaffHighlightMemberDomAttr,
        orderAttr: rosterStaffHighlightOrderDomAttr,
    });
}

test.describe('Roster staff shift highlight', () => {
    test.use({ viewport: { width: 1440, height: 900 } });
    test.afterEach(() => {
        runSql(`
            UPDATE roster_weeks
            SET is_live = FALSE, updated_at = NOW()
            WHERE id = 'a1000000-0000-0000-0000-000000000051';
            UPDATE roster_slots
            SET assignment_state = 'staff',
                staff_id = 'a1000000-0000-0000-0000-000000000031',
                deleted_at = NULL,
                updated_at = NOW()
            WHERE id = 'a1000000-0000-0000-0000-000000000071';
        `);
    });

    test('highlights the assigned slot outline in the row grid without changing cell borders', async ({ page }) => {
        await openRoster(page, { email: 'e2e-test@example.com' });
        await chooseRosterLayout(page, 'day_rows');

        const staffKey = await firstAssignedStaffKey(page);
        expect(staffKey).not.toBe('');

        const beforeHover = await gridSlotMetrics(page, staffKey);
        expect(beforeHover.slotCellCount).toBeGreaterThan(0);

        await hoverStaffRow(page, staffKey);

        const afterHover = await gridSlotMetrics(page, staffKey);
        expect(afterHover.highlightedCount).toBe(afterHover.slotCellCount);
        expect(afterHover.startCount).toBe(1);
        expect(afterHover.endCount).toBe(1);
        expect(afterHover.lastBoxShadow).not.toBe('none');
        expect(afterHover.lastBorderRightWidth).toBe(beforeHover.lastBorderRightWidth);
        expect(afterHover.lastControlLeft ?? 0).toBeCloseTo(beforeHover.lastControlLeft ?? 0, 0);
        expect(afterHover.lastControlWidth ?? 0).toBeCloseTo(beforeHover.lastControlWidth ?? 0, 0);
    });

    test('keeps staff-linked row highlights on a live read-only roster', async ({ page }) => {
        runSql(`
            UPDATE roster_slots
            SET assignment_state = 'staff',
                staff_id = 'a0000000-0000-0000-0000-000000000101',
                deleted_at = NULL,
                updated_at = NOW()
            WHERE id = 'a1000000-0000-0000-0000-000000000071';
        `);
        await openRoster(page, { email: 'e2e-test@example.com', ensureEditable: true });
        await chooseRosterLayout(page, 'day_rows');

        const staffKey = await firstAssignedStaffKey(page);
        const liveToggle = page
            .locator('[data-week-toolbar="roster"]')
            .locator(`[${toggleRootDomAttr}]`)
            .filter({ hasText: 'Live' });
        await expect(liveToggle.locator(`[${toggleInputDomAttr}]`)).not.toBeChecked();
        await expect(page.locator(`[${rosterStaffHighlightDefaultDomAttr}]`)).toHaveCount(0);

        const publishResponse = page.waitForResponse((response) =>
            response.request().method() === 'POST' && new URL(response.url()).pathname.includes('ToggleRosterWeekLiveStatus'),
        );
        await liveToggle.click();
        expect((await publishResponse).ok()).toBe(true);
        await expect(liveToggle.locator(`[${toggleInputDomAttr}]`)).toBeChecked({ timeout: E2E_TIMEOUT.liveUpdate });
        const ownDefaultOwner = page.locator(`[${rosterStaffHighlightDefaultDomAttr}]`);
        await expect(ownDefaultOwner).toHaveCount(1);
        const ownStaffKey = await ownDefaultOwner.getAttribute(rosterStaffHighlightDefaultDomAttr);
        expect(ownStaffKey).toBeTruthy();
        const ownMembers = page.locator(`[${rosterStaffHighlightMemberDomAttr}="${ownStaffKey}"]`);
        await expect(page.locator(`[${rosterStaffHighlightMemberDomAttr}="${ownStaffKey}"].is-linked-highlight-member`)).toHaveCount(await ownMembers.count());

        await hoverStaffRow(page, staffKey);
        const highlightedCells = page.locator(`.roster-grid [role="gridcell"][${rosterStaffHighlightMemberDomAttr}="${staffKey}"].is-linked-highlight-member`);
        await expect(highlightedCells.first()).toBeVisible();
        expect(await highlightedCells.count()).toBeGreaterThan(0);

        const draftResponse = page.waitForResponse((response) =>
            response.request().method() === 'POST' && new URL(response.url()).pathname.includes('ToggleRosterWeekLiveStatus'),
        );
        await liveToggle.click();
        expect((await draftResponse).ok()).toBe(true);
        await expect(liveToggle.locator(`[${toggleInputDomAttr}]`)).not.toBeChecked({ timeout: E2E_TIMEOUT.liveUpdate });
        await expect(page.locator(`[${rosterStaffHighlightDefaultDomAttr}]`)).toHaveCount(0);
    });

    test('highlights assigned shift cards in the day-column view', async ({ page }) => {
        await openRoster(page, { email: 'e2e-test@example.com' });
        await chooseRosterLayout(page, 'day_rows');

        const staffKey = await firstAssignedStaffKey(page);
        expect(staffKey).not.toBe('');

        await chooseRosterLayout(page, 'day_columns');

        await hoverStaffRow(page, staffKey);

        const highlightedCards = page.locator(`.roster-shift-card[${rosterStaffHighlightMemberDomAttr}="${staffKey}"].is-linked-highlight-member`);
        await expect(highlightedCards.first()).toBeVisible();
        await expect
            .poll(async () =>
                await highlightedCards.first().evaluate((card) => getComputedStyle(card).boxShadow),
            )
            .not.toBe('none');
    });

    test('filters authoritative wages by the pinned staff within one roster mount', async ({ page }) => {
        test.setTimeout(E2E_TIMEOUT.slowTest);
        const adminStaffKey = 'staff:a1000000-0000-0000-0000-000000000033';
        const alphaStaffKey = 'staff:a1000000-0000-0000-0000-000000000031';
        const fixtureSlotId = 'b3000000-0000-0000-0000-000000000001';
        try {
            runSql(`
                DROP TABLE IF EXISTS e2e_pinned_wage_week_backup;
                DROP TABLE IF EXISTS e2e_pinned_wage_day_backup;
                DROP TABLE IF EXISTS e2e_pinned_wage_staff_backup;
                DROP TABLE IF EXISTS e2e_pinned_wage_shift_type_backup;
                DROP TABLE IF EXISTS e2e_pinned_wage_pay_version_backup;
                DROP TABLE IF EXISTS e2e_pinned_wage_preference_backup;
                CREATE TABLE e2e_pinned_wage_week_backup AS
                    SELECT id, is_live, updated_at FROM roster_weeks
                    WHERE id = 'a1000000-0000-0000-0000-000000000051';
                CREATE TABLE e2e_pinned_wage_day_backup AS
                    SELECT id, row_count, is_closed, updated_at FROM roster_days
                    WHERE id = 'a1000000-0000-0000-0000-000000000061';
                CREATE TABLE e2e_pinned_wage_staff_backup AS
                    SELECT id, pay_assignment_mode, default_award_level_id, imported_xero_pay_item_id, is_active, archived_at, updated_at FROM staff
                    WHERE id = 'a1000000-0000-0000-0000-000000000033';
                CREATE TABLE e2e_pinned_wage_shift_type_backup AS
                    SELECT id, pay_assignment_mode, override_award_level_id, imported_xero_pay_item_id, is_active, archived_at, updated_at FROM shift_types
                    WHERE id = 'a1000000-0000-0000-0000-000000000133';
                CREATE TABLE e2e_pinned_wage_pay_version_backup AS
                    SELECT id, locked_at, locked_by_user_id, updated_at FROM staff_pay_versions
                    WHERE id = 'a1000000-0000-0000-0000-000000000303';
                CREATE TABLE e2e_pinned_wage_preference_backup AS
                    SELECT * FROM user_preferences
                    WHERE user_id = 'a0000000-0000-0000-0000-000000000003';

                UPDATE roster_weeks
                SET is_live = FALSE, updated_at = NOW()
                WHERE id = 'a1000000-0000-0000-0000-000000000051';

                UPDATE roster_days
                SET row_count = 4, is_closed = FALSE, updated_at = NOW()
                WHERE id = 'a1000000-0000-0000-0000-000000000061';

                UPDATE staff
                SET pay_assignment_mode = 'award_rate',
                    default_award_level_id = 'a1000000-0000-0000-0000-000000000111',
                    imported_xero_pay_item_id = NULL,
                    is_active = TRUE,
                    archived_at = NULL,
                    updated_at = NOW()
                WHERE id = 'a1000000-0000-0000-0000-000000000033';

                UPDATE shift_types
                SET pay_assignment_mode = 'staff_default',
                    override_award_level_id = NULL,
                    imported_xero_pay_item_id = NULL,
                    is_active = TRUE,
                    archived_at = NULL,
                    updated_at = NOW()
                WHERE id = 'a1000000-0000-0000-0000-000000000133';

                INSERT INTO user_preferences (user_id, roster_layout_mode, show_wage_estimates)
                VALUES ('a0000000-0000-0000-0000-000000000003', 'day_rows', TRUE)
                ON CONFLICT (user_id) DO UPDATE SET
                    roster_layout_mode = 'day_rows',
                    show_wage_estimates = TRUE,
                    updated_at = NOW();

                UPDATE staff_pay_versions
                SET locked_at = NOW(),
                    locked_by_user_id = 'a0000000-0000-0000-0000-000000000003',
                    updated_at = NOW()
                WHERE id = 'a1000000-0000-0000-0000-000000000303';

                INSERT INTO roster_slots (id, roster_day_id, staff_id, assignment_state, roster_week_slot_definition_id, row_index, starts_at, ends_at, timezone, shift_type_id)
                VALUES (
                    '${fixtureSlotId}',
                    'a1000000-0000-0000-0000-000000000061',
                    'a1000000-0000-0000-0000-000000000033',
                    'staff',
                    'a1000000-0000-0000-0000-000000000081',
                    1,
                    ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + TIME '12:00') AT TIME ZONE 'Australia/Melbourne',
                    ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + TIME '15:00') AT TIME ZONE 'Australia/Melbourne',
                    'Australia/Melbourne',
                    'a1000000-0000-0000-0000-000000000133'
                )
                ON CONFLICT (id) DO UPDATE SET
                    roster_day_id = EXCLUDED.roster_day_id,
                    staff_id = EXCLUDED.staff_id,
                    assignment_state = EXCLUDED.assignment_state,
                    roster_week_slot_definition_id = EXCLUDED.roster_week_slot_definition_id,
                    row_index = EXCLUDED.row_index,
                    starts_at = EXCLUDED.starts_at,
                    ends_at = EXCLUDED.ends_at,
                    timezone = EXCLUDED.timezone,
                    shift_type_id = EXCLUDED.shift_type_id,
                    deleted_at = NULL,
                    deleted_by_user_id = NULL,
                    delete_reason = NULL;
            `);

            await loginAsPrivilegedUserWithSeededPasskeySession(page);
            await openRoster(page, { email: 'e2e-admin@example.com', useCurrentSession: true });
            await ensureRosterLayout(page, 'day_rows');
            const wageFilterConfig = page.locator(`[${rosterWageFilterConfigDomAttr}]`);
            await expect(wageFilterConfig).toHaveCount(1);
            const rawWageFilterConfig = JSON.parse((await wageFilterConfig.getAttribute(rosterWageFilterConfigDomAttr)) ?? '{}');
            expect(rawWageFilterConfig.wageFilterEnabled).toBe(true);
            const weekTotal = page.locator('.roster-wage-summary-total');
            await expect(weekTotal).toBeVisible();
            const venueTotal = await weekTotal.textContent();
            const venueDayTotals = await page.locator('.roster-day-wage-total').allTextContents();

            const filterResponses: string[] = [];
            page.on('response', (response) => {
                if (response.status() === 200) filterResponses.push(response.url());
            });
            await page.evaluate((eventName) => {
                const state = window as Window & { __wageFilterRefreshCount?: number };
                state.__wageFilterRefreshCount = 0;
                document.addEventListener(eventName, () => { state.__wageFilterRefreshCount = (state.__wageFilterRefreshCount ?? 0) + 1; });
            }, liveFragmentsRefreshEvent);

            const pinAndWait = async (staffKey: string) => {
                const pin = page.locator(`[${rosterStaffHighlightPinDomAttr}="${staffKey}"]`).first();
                await expect(pin).toBeVisible();
                const previousRefreshCount = await page.evaluate(() => (window as Window & { __wageFilterRefreshCount?: number }).__wageFilterRefreshCount ?? 0);
                await pin.click();
                await expect(pin).toHaveAttribute('aria-pressed', 'true');
                await expect.poll(
                    () => page.evaluate(() => (window as Window & { __wageFilterRefreshCount?: number }).__wageFilterRefreshCount ?? 0),
                    { timeout: E2E_TIMEOUT.action },
                ).toBe(previousRefreshCount + 1);
                await expect.poll(
                    () => filterResponses.some((responseUrl) => {
                        const url = new URL(responseUrl);
                        return url.pathname.startsWith('/ShowRosterWeek')
                            && url.pathname.endsWith('Fragment')
                            && url.searchParams.get('pinnedStaffKey') === staffKey;
                    }),
                    { timeout: E2E_TIMEOUT.navigation },
                ).toBe(true);
                return pin;
            };

            const alphaPin = await pinAndWait(alphaStaffKey);
            await expect.poll(() => weekTotal.textContent(), { timeout: E2E_TIMEOUT.liveUpdate }).not.toBe(venueTotal);
            const alphaTotal = await weekTotal.textContent();
            await expect.poll(
                () => page.locator('.roster-day-wage-total').allTextContents(),
                { timeout: E2E_TIMEOUT.liveUpdate },
            ).not.toEqual(venueDayTotals);

            const passiveResponseStart = filterResponses.length;
            const actorPage = await page.context().newPage();
            try {
                await gotoWhenReady(actorPage, '/RosterWeeks', '#roster-content');
                await openRoster(actorPage, { email: 'e2e-admin@example.com', useCurrentSession: true });
                await ensureRosterLayout(actorPage, 'day_rows');
                await actorPage.getByRole('button', { name: 'Edit roster columns' }).click();
                const addRowButton = actorPage.getByRole('button', { name: 'Add shift row' }).first();
                const addRowUrl = await addRowButton.evaluate((button) => {
                    const form = button.closest('form');
                    return form?.getAttribute('hx-post') ?? form?.getAttribute('action') ?? '';
                });
                expect(addRowUrl).not.toBe('');
                const [addRowResponse] = await Promise.all([
                    actorPage.waitForResponse((response) => new URL(response.url()).pathname === new URL(addRowUrl, actorPage.url()).pathname, { timeout: E2E_TIMEOUT.navigation }),
                    addRowButton.click(),
                ]);
                expect(addRowResponse.status()).toBe(200);
                await expect.poll(
                    () => filterResponses.slice(passiveResponseStart).some((responseUrl) => new URL(responseUrl).searchParams.get('pinnedStaffKey') === alphaStaffKey),
                    { timeout: E2E_TIMEOUT.liveUpdate },
                ).toBe(true);
                await expect(alphaPin).toHaveAttribute('aria-pressed', 'true');
                await expect(weekTotal).toHaveText(alphaTotal ?? '');
            } finally {
                await actorPage.close();
            }

            const adminPin = await pinAndWait(adminStaffKey);
            await expect.poll(() => weekTotal.textContent(), { timeout: E2E_TIMEOUT.liveUpdate }).not.toBe(alphaTotal);
            await expect(alphaPin).toHaveAttribute('aria-pressed', 'false');

            await adminPin.click();
            await expect(adminPin).toHaveAttribute('aria-pressed', 'false');
            await expect(weekTotal).toHaveText(venueTotal ?? '');

            await pinAndWait(alphaStaffKey);
            await Promise.all([
                page.waitForURL((url) => url.pathname === '/ShowRosterWeek' && url.searchParams.get('weekOffset') === '1', { timeout: E2E_TIMEOUT.navigation }),
                page.getByRole('link', { name: 'Next week' }).click(),
            ]);
            expect(new URL(page.url()).searchParams.has('pinnedStaffKey')).toBe(false);
            await expect(page.locator(`[${rosterStaffHighlightPinDomAttr}="${alphaStaffKey}"]`).first()).toHaveAttribute('aria-pressed', 'false');
            await Promise.all([
                page.waitForURL((url) => url.pathname === '/ShowRosterWeek' && url.searchParams.get('weekOffset') === '0', { timeout: E2E_TIMEOUT.navigation }),
                page.getByRole('link', { name: 'Previous week' }).click(),
            ]);
            expect(new URL(page.url()).searchParams.has('pinnedStaffKey')).toBe(false);
            await expect(weekTotal).toHaveText(venueTotal ?? '');

            await pinAndWait(alphaStaffKey);
            await page.reload();
            await expect(page.locator(`[${rosterStaffHighlightPinDomAttr}="${alphaStaffKey}"]`).first()).toHaveAttribute('aria-pressed', 'false');
            await expect(weekTotal).toHaveText(venueTotal ?? '');

            runSql(`DELETE FROM user_preferences WHERE user_id = 'a0000000-0000-0000-0000-000000000003';`);
            await page.reload();
            await expect(page.locator('.roster-wage-summary')).toHaveCount(0);
            const disabledWageConfig = page.locator(`[${rosterWageFilterConfigDomAttr}]`);
            expect(JSON.parse((await disabledWageConfig.getAttribute(rosterWageFilterConfigDomAttr)) ?? '{}').wageFilterEnabled).toBe(false);
            const disabledPin = page.locator(`[${rosterStaffHighlightPinDomAttr}="${alphaStaffKey}"]`).first();
            await disabledPin.click();
            await expect(disabledPin).toHaveAttribute('aria-pressed', 'true');
        } finally {
            runSql(`
                UPDATE roster_weeks AS target
                SET is_live = backup.is_live,
                    updated_at = backup.updated_at
                FROM e2e_pinned_wage_week_backup AS backup
                WHERE target.id = backup.id;
                UPDATE roster_days AS target
                SET row_count = backup.row_count,
                    is_closed = backup.is_closed,
                    updated_at = backup.updated_at
                FROM e2e_pinned_wage_day_backup AS backup
                WHERE target.id = backup.id;
                UPDATE staff AS target
                SET pay_assignment_mode = backup.pay_assignment_mode,
                    default_award_level_id = backup.default_award_level_id,
                    imported_xero_pay_item_id = backup.imported_xero_pay_item_id,
                    is_active = backup.is_active,
                    archived_at = backup.archived_at,
                    updated_at = backup.updated_at
                FROM e2e_pinned_wage_staff_backup AS backup
                WHERE target.id = backup.id;
                UPDATE shift_types AS target
                SET pay_assignment_mode = backup.pay_assignment_mode,
                    override_award_level_id = backup.override_award_level_id,
                    imported_xero_pay_item_id = backup.imported_xero_pay_item_id,
                    is_active = backup.is_active,
                    archived_at = backup.archived_at,
                    updated_at = backup.updated_at
                FROM e2e_pinned_wage_shift_type_backup AS backup
                WHERE target.id = backup.id;
                DELETE FROM user_preferences
                WHERE user_id = 'a0000000-0000-0000-0000-000000000003';
                INSERT INTO user_preferences
                SELECT * FROM e2e_pinned_wage_preference_backup;
                UPDATE roster_slots
                SET deleted_at = NOW(),
                    deleted_by_user_id = 'a0000000-0000-0000-0000-000000000003',
                    delete_reason = 'E2E pinned wage filter cleanup',
                    updated_at = NOW()
                WHERE id = '${fixtureSlotId}';
                UPDATE staff_pay_versions AS target
                SET locked_at = backup.locked_at,
                    locked_by_user_id = backup.locked_by_user_id,
                    updated_at = backup.updated_at
                FROM e2e_pinned_wage_pay_version_backup AS backup
                WHERE target.id = backup.id;
                DROP TABLE e2e_pinned_wage_week_backup;
                DROP TABLE e2e_pinned_wage_day_backup;
                DROP TABLE e2e_pinned_wage_staff_backup;
                DROP TABLE e2e_pinned_wage_shift_type_backup;
                DROP TABLE e2e_pinned_wage_pay_version_backup;
                DROP TABLE e2e_pinned_wage_preference_backup;
            `);
        }
    });

    test('toggles a persistent staff highlight from the locate shifts button', async ({ page }) => {
        await openRoster(page, { email: 'e2e-test@example.com' });
        await chooseRosterLayout(page, 'day_rows');

        const staffKey = await firstAssignedStaffKey(page);
        expect(staffKey).not.toBe('');

        await toggleLocateShifts(page, staffKey);

        const highlightedCells = page.locator(`.roster-grid [role="gridcell"][${rosterStaffHighlightMemberDomAttr}="${staffKey}"].is-linked-highlight-member`);
        await expect(highlightedCells.first()).toBeVisible();

        await page.locator('.roster-grid').hover();
        await expect(highlightedCells.first()).toBeVisible();

        const staffRow = page.locator(`[${rosterStaffPanelSortRowDomAttr}][${rosterStaffHighlightSourceDomAttr}="${staffKey}"]`).first();
        await staffRow.getByRole('button', { name: /Locate shifts for/ }).evaluate((button) => {
            if (!(button instanceof HTMLElement)) throw new Error('Expected locate button');
            button.click();
        });
        await expect(highlightedCells).toHaveCount(0);
    });
});
