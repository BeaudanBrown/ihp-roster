import { expect, test } from '@playwright/test';
import {
    dialogOverlayMountDomId,
    timesheetsTimesheetSidePanelPanelDomAttr,
    timesheetsTimesheetSidePanelTabDomAttr,
    timesheetsTimesheetSidePanelToggleDomAttr,
    timesheetsTimesheetStaffHighlightMemberDomAttr,
    timesheetsTimesheetStaffHighlightPinDomAttr,
    timesheetsTimesheetStaffHighlightSourceDomAttr,
} from '../frontend/ts/generated/contracts';
import { defaultE2ERosterGroupId } from './support/roster';
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady } from './support/runtime';
import { loginAs } from './support/session';
import { openTimesheetFilterSection, openTimesheetSettings, resetTimesheetDisplayPreferences } from './support/timesheets';
import { runSql } from './support/database';

const secondRosterGroupId = 'a1000000-0000-0000-0000-000000000213';

function ensureSecondRosterGroup() {
    runSql(`
        INSERT INTO roster_groups (id, venue_id, name, sort_order, is_active, is_default, archived_at)
        VALUES ('${secondRosterGroupId}', 'a1000000-0000-0000-0000-000000000001', 'Second group', 20, TRUE, FALSE, NULL)
        ON CONFLICT (id) DO UPDATE SET
            is_active = TRUE,
            archived_at = NULL,
            updated_at = NOW();
    `);
}

test.describe('Timesheets shared SidePanel', () => {
    test.describe.configure({ timeout: E2E_TIMEOUT.slowTest });
    test.beforeEach(() => ensureSecondRosterGroup());
    test.afterEach(() => {
        resetTimesheetDisplayPreferences('e2e-test@example.com');
        resetTimesheetDisplayPreferences('e2e-worker@example.com');
        runSql(`
            UPDATE roster_groups
            SET is_active = FALSE, archived_at = NOW(), updated_at = NOW()
            WHERE id = '${secondRosterGroupId}';
        `);
    });

    test('keeps manager inventory complete while filtering and supports highlight, pin, and profile launch', async ({ page }) => {
        await page.setViewportSize({ width: 1440, height: 900 });
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');

        const panel = page.locator(`[${timesheetsTimesheetSidePanelPanelDomAttr}]`);
        await expect(panel).toBeVisible();
        await expect(page.locator(`[${timesheetsTimesheetSidePanelToggleDomAttr}]`)).toBeVisible();

        const rows = panel.locator(`[${timesheetsTimesheetStaffHighlightSourceDomAttr}]`);
        const initialRowCount = await rows.count();
        expect(initialRowCount).toBeGreaterThan(1);

        const firstCard = page.locator(`[${timesheetsTimesheetStaffHighlightMemberDomAttr}]`).first();
        const staffKey = await firstCard.getAttribute(timesheetsTimesheetStaffHighlightMemberDomAttr);
        expect(staffKey).toBeTruthy();
        const rowWithCard = panel.locator(`[${timesheetsTimesheetStaffHighlightSourceDomAttr}="${staffKey}"]`);
        const matchingCards = page.locator(`[${timesheetsTimesheetStaffHighlightMemberDomAttr}="${staffKey}"]`);
        await expect(rowWithCard).toHaveCount(1);

        await rowWithCard.hover();
        await expect(matchingCards.first()).toHaveClass(/is-linked-highlight-member/);

        const pin = rowWithCard.locator(`[${timesheetsTimesheetStaffHighlightPinDomAttr}]`);
        await pin.click();
        await expect(pin).toHaveAttribute('aria-pressed', 'true');
        await expect(page.locator(`#${dialogOverlayMountDomId}`).getByRole('dialog')).toHaveCount(0);

        await openTimesheetSettings(page);
        const section = await openTimesheetFilterSection(page, 'Staff');
        await section.getByRole('checkbox').first().check();
        await page.getByRole('button', { name: 'Apply', exact: true }).click();
        await expect(page).toHaveURL(/staffFilterIds=/, { timeout: E2E_TIMEOUT.navigation });
        await expect(panel.locator(`[${timesheetsTimesheetStaffHighlightSourceDomAttr}]`)).toHaveCount(initialRowCount);
        await expect(panel.locator(`[${timesheetsTimesheetSidePanelTabDomAttr}="settings"]`)).toHaveAttribute('aria-selected', 'true');

        await page.getByRole('tab', { name: 'Staff' }).click();
        await panel.locator(`[${timesheetsTimesheetStaffHighlightSourceDomAttr}]`).first().click();
        await expect(page.locator(`#${dialogOverlayMountDomId}`).getByRole('dialog')).toBeVisible();
    });

    test('keeps roster-group filtering active through shell navigation', async ({ page }) => {
        await page.setViewportSize({ width: 1440, height: 900 });
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');

        await expect(page.locator('.timesheet-entry-card')).not.toHaveCount(0);
        await openTimesheetSettings(page);
        const section = await openTimesheetFilterSection(page, 'Roster groups');
        await expect(section.getByRole('checkbox', { name: 'Main', exact: true })).toHaveValue(defaultE2ERosterGroupId);
        await section.getByRole('checkbox', { name: 'Second group', exact: true }).check();
        await page.getByRole('button', { name: 'Apply', exact: true }).click();
        await expect(page).toHaveURL(new RegExp(`rosterGroupFilterIds=${secondRosterGroupId}`), { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('.timesheet-entry-card')).toHaveCount(0);
        await expect(page.locator(`[${timesheetsTimesheetSidePanelTabDomAttr}="settings"]`)).toHaveAttribute('aria-selected', 'true');

        await page.getByRole('link', { name: '>' }).click();
        await expect(page).toHaveURL(new RegExp(`rosterGroupFilterIds=${secondRosterGroupId}`), { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator(`[${timesheetsTimesheetSidePanelTabDomAttr}="settings"]`)).toHaveAttribute('aria-selected', 'true');
        const reopened = await openTimesheetFilterSection(page, 'Roster groups');
        await expect(reopened.getByRole('checkbox', { name: 'Second group', exact: true })).toBeChecked();
    });

    test('hides roster-group filtering when the manager has only one active group', async ({ page }) => {
        runSql(`UPDATE roster_groups SET is_active = FALSE, updated_at = NOW() WHERE id = '${secondRosterGroupId}';`);
        await page.setViewportSize({ width: 1440, height: 900 });
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, `/Timesheets?rosterGroupFilterIds=${defaultE2ERosterGroupId}`, '#timesheet-week-shell');
        await expect(page).toHaveURL(/\/ShowTimesheetWindow\?anchorDate=\d{4}-\d{2}-\d{2}$/);
        await page.locator('#timesheet-filters-button').click();
        await expect(page.locator(`#${dialogOverlayMountDomId} summary`, { hasText: 'Roster groups' })).toHaveCount(0);
    });

    test('renders a Settings-only tools shelf for ordinary staff', async ({ page }) => {
        await page.setViewportSize({ width: 390, height: 844 });
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');

        const mobilePanelToggle = page.getByRole('button', { name: 'Open Timesheet tools' });
        await expect(mobilePanelToggle).toBeVisible();
        await mobilePanelToggle.click();

        const panel = page.locator(`[${timesheetsTimesheetSidePanelPanelDomAttr}]`);
        await expect(panel).toBeVisible();
        await expect(panel.getByRole('heading', { name: 'Settings' })).toBeVisible();
        await expect(panel.getByRole('tab')).toHaveCount(0);
        await expect(panel.locator(`[${timesheetsTimesheetStaffHighlightSourceDomAttr}]`)).toHaveCount(0);
        await expect(page.locator(`[${timesheetsTimesheetSidePanelToggleDomAttr}]`)).toBeHidden();
        await page.getByRole('button', { name: 'Close Timesheet tools', exact: true }).click();
        await page.locator('#timesheet-filters-button').click();
        await expect(page.locator(`#${dialogOverlayMountDomId} summary`, { hasText: 'Roster groups' })).toHaveCount(0);
    });
});
