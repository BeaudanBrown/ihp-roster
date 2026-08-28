import { expect, test } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady } from './support/runtime';
import { loginAsPrivilegedUserWithSeededPasskeySession, openAdminWithSeededPasskeySession } from './support/passkeys';
import { openRoster, openRosterSettings } from './support/roster';
import { runSql } from './support/database';

const venueId = 'a1000000-0000-0000-0000-000000000001';
const rosterGroupId = 'a1000000-0000-0000-0000-000000000211';
const staffId = 'a1000000-0000-0000-0000-000000000031';

function seedCurrentWeekHoliday() {
    runSql(`
        INSERT INTO public_holidays (jurisdiction, holiday_date, name, is_regional, source, source_id)
        VALUES (
            'VIC',
            date_trunc('week', CURRENT_DATE)::date,
            'E2E Roster Holiday',
            FALSE,
            'e2e',
            'admin-roster-ui-polish'
        )
        ON CONFLICT (jurisdiction, holiday_date, name, region) DO UPDATE SET
            is_regional = FALSE,
            updated_at = NOW();
    `);
}

test.describe('Admin and roster UI polish', () => {
    test.describe.configure({ retries: 0, timeout: 20_000 });

    test('centres roster settings controls and positions public holiday indicators', async ({ page }) => {
        await page.setViewportSize({ width: 1280, height: 900 });
        seedCurrentWeekHoliday();
        runSql(`UPDATE venue_config SET roster_end_times_enabled = TRUE WHERE venue_id = '${venueId}'`);
        runSql(`
            INSERT INTO user_preferences (user_id, roster_layout_mode, show_wage_estimates)
            VALUES ('a0000000-0000-0000-0000-000000000003', 'day_columns', TRUE)
            ON CONFLICT (user_id) DO UPDATE SET
                roster_layout_mode = 'day_columns',
                show_wage_estimates = TRUE,
                updated_at = NOW();
        `);

        await openRoster(page, { email: 'e2e-admin@example.com', ensureEditable: false, rosterLayoutMode: 'day_columns' });

        const holidayDate = page.locator('.roster-day-column-header .roster-day-date', { hasText: 'Mon' }).first();
        await expect(holidayDate.locator('.roster-public-holiday-indicator')).toHaveAttribute('title', 'E2E Roster Holiday');
        const holidayMetrics = await holidayDate.evaluate((element) => {
            const indicator = element.querySelector('.roster-public-holiday-indicator') as HTMLElement | null;
            const label = Array.from(element.children).find((child) => child !== indicator) as HTMLElement | undefined;
            if (!indicator || !label) throw new Error('Expected holiday indicator and day label');
            const indicatorRect = indicator.getBoundingClientRect();
            const labelRect = label.getBoundingClientRect();
            return { indicatorLeft: indicatorRect.left, labelLeft: labelRect.left };
        });
        expect(holidayMetrics.indicatorLeft).toBeLessThan(holidayMetrics.labelLeft);

        const dayHeaderMetrics = await page.locator('.roster-day-column-header').first().evaluate((header) => {
            const headerRect = header.getBoundingClientRect();
            const centerY = headerRect.top + headerRect.height / 2;
            const rectFor = (selector: string) => {
                const element = header.querySelector(selector) as HTMLElement | null;
                if (!element) throw new Error(`Expected ${selector}`);
                const rect = element.getBoundingClientRect();
                return rect.top + rect.height / 2;
            };
            return {
                centerY,
                headingCenterY: rectFor('.roster-day-heading'),
                wageCenterY: rectFor('.roster-day-column-wage-slot'),
                controlCenterY: rectFor('.roster-day-column-control-slot'),
            };
        });
        expect(Math.abs(dayHeaderMetrics.headingCenterY - dayHeaderMetrics.centerY)).toBeLessThanOrEqual(2);
        expect(Math.abs(dayHeaderMetrics.wageCenterY - dayHeaderMetrics.centerY)).toBeLessThanOrEqual(2);
        expect(Math.abs(dayHeaderMetrics.controlCenterY - dayHeaderMetrics.centerY)).toBeLessThanOrEqual(2);

        await openRosterSettings(page);
        const layoutMetrics = await page.locator('.roster-layout-mode-group').evaluate((group) => {
            const buttons = Array.from(group.querySelectorAll('label.btn')) as HTMLElement[];
            return buttons.map((button) => {
                const style = window.getComputedStyle(button);
                return { justifyContent: style.justifyContent, textAlign: style.textAlign };
            });
        });
        expect(layoutMetrics).toHaveLength(2);
        for (const button of layoutMetrics) {
            expect(button.justifyContent).toBe('center');
            expect(button.textAlign).toBe('center');
        }
    });

    test('keeps admin shift type controls and venue settings grid aligned', async ({ page }) => {
        await page.setViewportSize({ width: 1600, height: 1000 });

        await openAdminWithSeededPasskeySession(page);
        await page.getByRole('button', { name: 'Shift Types' }).click();
        const firstShiftTypeRow = page.locator('form[data-admin-shift-type-row]').first();
        await expect(firstShiftTypeRow).toBeVisible();
        const shiftTypeMetrics = await firstShiftTypeRow.evaluate((row) => {
            const controls = Array.from(row.querySelectorAll('.row.g-2.align-items-end > div')) as HTMLElement[];
            return controls.map((control) => {
                const rect = control.getBoundingClientRect();
                return { top: rect.top, bottom: rect.bottom };
            });
        });
        expect(shiftTypeMetrics).toHaveLength(4);
        const firstBottom = shiftTypeMetrics[0].bottom;
        for (const metric of shiftTypeMetrics) {
            expect(Math.abs(metric.bottom - firstBottom)).toBeLessThanOrEqual(2);
        }

        await page.getByRole('button', { name: 'Venue Settings' }).click();
        const settingsGrid = page.locator('#admin-venue-settings-fragment .admin-settings-grid');
        await expect(settingsGrid).toBeVisible();
        const settingsMetrics = await settingsGrid.evaluate((grid) => {
            const gridRect = grid.getBoundingClientRect();
            const gridStyle = window.getComputedStyle(grid);
            const cards = Array.from(grid.querySelectorAll('.admin-setting-row')) as HTMLElement[];
            return {
                gridWidth: gridRect.width,
                columns: gridStyle.gridTemplateColumns.split(' ').filter(Boolean),
                cards: cards.map((card) => {
                    const rect = card.getBoundingClientRect();
                    return { width: rect.width, left: rect.left - gridRect.left };
                }),
            };
        });
        expect(settingsMetrics.columns.length).toBeLessThanOrEqual(4);
        expect(settingsMetrics.cards.length).toBeGreaterThanOrEqual(3);
        for (const card of settingsMetrics.cards) {
            expect(Math.abs(settingsMetrics.cards[0].width - card.width)).toBeLessThanOrEqual(1);
        }
        expect(settingsMetrics.cards[0].width).toBeLessThan(settingsMetrics.gridWidth / 3);
        expect(settingsMetrics.cards[0].left).toBeLessThanOrEqual(1);
        expect(settingsMetrics.cards[1].left).toBeGreaterThan(settingsMetrics.cards[0].left);
        expect(settingsMetrics.cards[2].left).toBeGreaterThan(settingsMetrics.cards[1].left);
    });

    test('lets venue admins submit staff unavailability from the staff edit page', async ({ page }) => {
        await page.setViewportSize({ width: 1280, height: 900 });
        await loginAsPrivilegedUserWithSeededPasskeySession(page, 'e2e-admin@example.com', 'test-password-123');
        await gotoWhenReady(page, `/EditStaff?staffId=${staffId}&anchorDate=2025-01-06&rosterGroupId=${rosterGroupId}&section=profile`, '#staff-sections');

        const roleSelect = page.locator('#staff-edit-form select[name="venueRole"]');
        await expect(roleSelect).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(roleSelect).toHaveValue('worker');
        await expect(roleSelect.locator('option')).toContainText(['Worker', 'Manager', 'Venue Admin']);

        await page.locator('#staff-profile-leave-heading button').click({ timeout: E2E_TIMEOUT.action });
        await expect(page.locator('#staff-leave-request-form')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });

        const startDateBefore = await page.locator('#staff-leave-request-form input[name="startDate"]').inputValue();
        const endDateBefore = await page.locator('#staff-leave-request-form input[name="endDate"]').inputValue();
        const note = `e2e staff modal unavailable ${Date.now()}`;
        await page.locator('#staff-leave-request-form textarea[name="notes"]').fill(note, { timeout: E2E_TIMEOUT.action });
        await page.locator('#staff-leave-request-form button[type="submit"]').click({ timeout: E2E_TIMEOUT.action });

        await expect(page.locator('#staff-leave-requests-list-fragment')).toContainText(note, { timeout: E2E_TIMEOUT.assertion });
        await expect(page.locator('#staff-leave-request-form textarea[name="notes"]')).toHaveValue('', { timeout: E2E_TIMEOUT.assertion });
        await expect(page.locator('#staff-leave-request-form input[name="startDate"]')).toHaveValue(startDateBefore, { timeout: E2E_TIMEOUT.assertion });
        await expect(page.locator('#staff-leave-request-form input[name="endDate"]')).toHaveValue(endDateBefore, { timeout: E2E_TIMEOUT.assertion });
    });
});
