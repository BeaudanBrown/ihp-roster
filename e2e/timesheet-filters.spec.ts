import { expect, test } from '@playwright/test';
import { gotoWhenReady } from './support/runtime';
import { E2E_TIMEOUT } from './timeouts';
import { loginAs } from './support/session';
import { openTimesheetFilterSection, openTimesheetSettings, resetTimesheetDisplayPreferences } from './support/timesheets';
import { dialogOverlayMountDomId, filterSelectionSectionDomAttr } from '../frontend/ts/generated/contracts';

const modal = `#${dialogOverlayMountDomId}`;
const sections = `[${filterSelectionSectionDomAttr}]`;

test.describe.configure({ timeout: E2E_TIMEOUT.slowTest });
test.afterEach(() => resetTimesheetDisplayPreferences(['e2e-admin@example.com', 'e2e-worker@example.com']));

test('stages multiple filters, preserves them across navigation, and clears immediately', async ({ page }) => {
    await loginAs(page, 'e2e-admin@example.com', 'test-password-123');
    await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');
    await expect(page.getByRole('button', { name: 'Clear filters', exact: true })).toBeDisabled();
    await page.evaluate(() => { document.documentElement.dataset.filterTest = 'same-page'; });
    await page.locator('#timesheet-filters-button').click();
    const staff = page.locator(`${modal} ${sections}`).filter({ has: page.locator('summary', { hasText: 'Staff' }) });
    const shifts = page.locator(`${modal} ${sections}`).filter({ has: page.locator('summary', { hasText: 'Shift types' }) });
    await expect(staff).not.toHaveAttribute('open');
    await staff.locator('summary').click();
    const checkboxes = staff.getByRole('checkbox');
    const first = await checkboxes.nth(0).getAttribute('value');
    const second = await checkboxes.nth(1).getAttribute('value');
    await checkboxes.nth(0).check();
    await checkboxes.nth(1).check();
    await expect(staff.locator('summary')).toContainText('2 selected');
    await expect(page).not.toHaveURL(/staffFilterIds/);
    await shifts.locator('summary').click();
    await shifts.getByRole('checkbox').first().check();
    await expect(staff).toHaveAttribute('open');
    await page.getByRole('button', { name: 'Apply', exact: true }).click();
    await expect(page.locator(modal)).toBeEmpty();
    await expect(page.locator('#timesheet-filters-button')).toHaveText('Filters · 2');
    await expect(page.locator('html')).toHaveAttribute('data-filter-test', 'same-page');
    const params = new URL(page.url()).searchParams;
    expect(params.getAll('staffFilterIds').sort()).toEqual([first, second].sort());
    expect(params.getAll('shiftTypeFilterIds')).toHaveLength(1);

    await page.locator('#timesheet-filters-button').click();
    await staff.locator('summary').click();
    await expect(staff.getByRole('checkbox').nth(0)).toBeChecked();
    await staff.getByRole('button', { name: 'Clear', exact: true }).click();
    await expect(staff.locator('summary')).toContainText('All');
    await page.keyboard.press('Escape');
    await expect(page.locator(modal)).toBeEmpty();
    expect(new URL(page.url()).searchParams.getAll('staffFilterIds').sort()).toEqual([first, second].sort());

    const previousAnchor = new URL(page.url()).searchParams.get('anchorDate');
    await page.getByRole('link', { name: '>', exact: true }).click();
    await expect.poll(() => new URL(page.url()).searchParams.get('anchorDate')).not.toBe(previousAnchor);
    await expect(page.locator('#timesheet-filters-button')).toHaveText('Filters · 2');
    expect(new URL(page.url()).searchParams.getAll('staffFilterIds').sort()).toEqual([first, second].sort());
    await page.getByRole('link', { name: 'Clear filters', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Clear filters', exact: true })).toBeDisabled();
    await expect(page).not.toHaveURL(/FilterIds/);
    await page.goBack();
    await expect(page.locator('#timesheet-filters-button')).toHaveText('Filters · 2');
    await page.reload();
    await expect(page.locator('#timesheet-filters-button')).toHaveText('Filters · 2');
    await page.goForward();
    await expect(page.getByRole('button', { name: 'Clear filters', exact: true })).toBeDisabled();
});

test('workers can filter shift types without staff or roster-group controls', async ({ page }) => {
    await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
    await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');
    await page.locator('#timesheet-filters-button').click();
    await expect(page.locator(`${modal} ${sections}`)).toHaveCount(1);
    await expect(page.locator(`${modal} ${sections}`)).toHaveAttribute('open');
    await expect(page.locator(`${modal} summary`)).toContainText('Shift types');
    await page.locator(`${modal} input[type=checkbox]`).first().check();
    await page.getByRole('button', { name: 'Apply', exact: true }).click();
    await expect(page.locator(modal)).toBeEmpty();
    await expect(page).toHaveURL(/shiftTypeFilterIds/);
});

test('turning Manager mode off clears Staff but retains shift-type selections', async ({ page }) => {
    await loginAs(page, 'e2e-admin@example.com', 'test-password-123');
    await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');
    const staff = await openTimesheetFilterSection(page, 'Staff');
    await staff.getByRole('checkbox').first().check();
    const shifts = await openTimesheetFilterSection(page, 'Shift types');
    await shifts.getByRole('checkbox').first().check();
    await page.getByRole('button', { name: 'Apply', exact: true }).click();
    await expect(page.locator('#timesheet-filters-button')).toHaveText('Filters · 2');
    await openTimesheetSettings(page);
    await Promise.all([
        page.waitForEvent('framenavigated', frame => frame === page.mainFrame()),
        page.locator('label[for="timesheet-manager-mode-toggle"]').click(),
    ]);
    await expect(page.locator('#timesheet-filters-button')).toHaveText('Filters · 1');
    await expect(page).not.toHaveURL(/staffFilterIds/);
    await expect(page).toHaveURL(/shiftTypeFilterIds/);
    await openTimesheetSettings(page);
    await Promise.all([
        page.waitForEvent('framenavigated', frame => frame === page.mainFrame()),
        page.locator('label[for="timesheet-manager-mode-toggle"]').click(),
    ]);
    await expect(page.locator('#timesheet-filters-button')).toHaveText('Filters · 1');
    const reopened = await openTimesheetFilterSection(page, 'Staff');
    await expect(reopened.locator('input:checked')).toHaveCount(0);
});

test('standalone filter page applies through native GET without requiring a week shell', async ({ page }) => {
    await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
    await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');
    const anchor = new URL(page.url()).searchParams.get('anchorDate');
    await gotoWhenReady(page, `/ShowTimesheetFilters?anchorDate=${anchor}`, '#timesheet-filters-form');
    await expect(page.locator('#timesheet-week-shell')).toHaveCount(0);
    await page.getByRole('checkbox').first().check();
    await page.getByRole('button', { name: 'Apply', exact: true }).click();
    await expect(page.locator('#timesheet-week-shell')).toBeVisible();
    await expect(page.locator('#timesheet-filters-button')).toHaveText('Filters · 1');
});
