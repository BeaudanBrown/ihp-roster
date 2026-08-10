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
import {
    E2E_TIMEOUT,
    gotoWhenReady,
    loginAs,
    openTimesheetSettings,
    resetTimesheetDisplayPreferences,
} from './test-helpers';

test.describe('Timesheets shared SidePanel', () => {
    test.describe.configure({ timeout: E2E_TIMEOUT.slowTest });
    test.afterEach(() => {
        resetTimesheetDisplayPreferences('e2e-test@example.com');
        resetTimesheetDisplayPreferences('e2e-worker@example.com');
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
        const filter = page.locator('#timesheet-staff-filter');
        const selectedValue = await filter.locator('option:not([value=""])').first().getAttribute('value');
        await filter.selectOption(selectedValue ?? '');
        await expect(page).toHaveURL(/staffFilterId=/, { timeout: E2E_TIMEOUT.navigation });
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
        const rosterGroupFilter = page.locator('#timesheet-roster-group-filter');
        const rosterGroupId = await rosterGroupFilter.locator('option:not([value=""])').first().getAttribute('value');
        expect(rosterGroupId).toBeTruthy();

        await rosterGroupFilter.selectOption(rosterGroupId ?? '');
        await expect(page).toHaveURL(new RegExp(`rosterGroupFilterId=${rosterGroupId}`), { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('.timesheet-entry-card')).toHaveCount(0);
        await expect(page.locator(`[${timesheetsTimesheetSidePanelTabDomAttr}="settings"]`)).toHaveAttribute('aria-selected', 'true');

        await page.getByRole('link', { name: '>' }).click();
        await expect(page).toHaveURL(new RegExp(`rosterGroupFilterId=${rosterGroupId}`), { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#timesheet-roster-group-filter')).toHaveValue(rosterGroupId ?? '');
        await expect(page.locator(`[${timesheetsTimesheetSidePanelTabDomAttr}="settings"]`)).toHaveAttribute('aria-selected', 'true');
    });

    test('renders a Settings-only stacked panel for ordinary staff', async ({ page }) => {
        await page.setViewportSize({ width: 390, height: 844 });
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');

        const panel = page.locator(`[${timesheetsTimesheetSidePanelPanelDomAttr}]`);
        await expect(panel).toBeVisible();
        await expect(panel.getByRole('heading', { name: 'Settings' })).toBeVisible();
        await expect(panel.getByRole('tab')).toHaveCount(0);
        await expect(panel.locator(`[${timesheetsTimesheetStaffHighlightSourceDomAttr}]`)).toHaveCount(0);
        await expect(page.locator('#timesheet-roster-group-filter')).toHaveCount(0);
        await expect(page.locator(`[${timesheetsTimesheetSidePanelToggleDomAttr}]`)).toBeHidden();
    });
});
