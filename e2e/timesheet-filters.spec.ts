import { expect, test } from '@playwright/test';
import { gotoWhenReady } from './support/runtime';
import { E2E_TIMEOUT } from './timeouts';
import { loginAs } from './support/session';
import { openTimesheetFilters, openTimesheetFilterSection, openTimesheetSettings, resetTimesheetDisplayPreferences } from './support/timesheets';
import { dialogOverlayMountDomId, filterSelectionSectionDomAttr } from '../frontend/ts/generated/contracts';

const modal = `#${dialogOverlayMountDomId}`;
const sections = `[${filterSelectionSectionDomAttr}]`;

test.describe.configure({ timeout: E2E_TIMEOUT.slowTest });
test.afterEach(() => resetTimesheetDisplayPreferences(['e2e-admin@example.com', 'e2e-worker@example.com']));

test('Settings stages multiple filters, preserves them across navigation, and clears immediately', async ({ page }) => {
    await loginAs(page, 'e2e-admin@example.com', 'test-password-123');
    await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');
    await expect(page.locator('#timesheet-week-toolbar #timesheet-filters-button')).toHaveCount(0);
    await openTimesheetSettings(page);
    await expect(page.locator('#timesheet-side-panel-content #timesheet-filters-button')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Clear filters', exact: true })).toBeDisabled();
    await page.evaluate(() => { document.documentElement.dataset.filterTest = 'same-page'; });
    await openTimesheetFilters(page);
    const staff = page.locator(`${modal} ${sections}`).filter({ has: page.getByRole('button', { name: 'Staff', exact: true }) });
    const shifts = page.locator(`${modal} ${sections}`).filter({ has: page.getByRole('button', { name: 'Shift types', exact: true }) });
    const staffToggle = staff.getByRole('button', { name: 'Staff', exact: true });
    const shiftToggle = shifts.getByRole('button', { name: 'Shift types', exact: true });
    await expect(staffToggle).toHaveAttribute('aria-expanded', 'false');
    await staffToggle.click();
    const checkboxes = staff.getByRole('checkbox');
    const first = await checkboxes.nth(0).getAttribute('value');
    const second = await checkboxes.nth(1).getAttribute('value');
    await checkboxes.nth(0).check();
    await checkboxes.nth(1).check();
    await expect(staffToggle).toContainText('2 selected');
    await expect(page).not.toHaveURL(/staffFilterIds/);
    await shiftToggle.click();
    await shifts.getByRole('checkbox').first().check();
    await expect(staffToggle).toHaveAttribute('aria-expanded', 'true');
    await expect(staff.getByRole('checkbox').first()).toBeVisible();
    await page.getByRole('button', { name: 'Apply', exact: true }).click();
    await expect(page.locator(modal)).toBeEmpty();
    await expect(page.locator('#timesheet-filters-button')).toHaveText('Filters · 2');
    await expect(page.locator('html')).toHaveAttribute('data-filter-test', 'same-page');
    const params = new URL(page.url()).searchParams;
    expect(params.getAll('staffFilterIds').sort()).toEqual([first, second].sort());
    expect(params.getAll('shiftTypeFilterIds')).toHaveLength(1);

    await openTimesheetFilters(page);
    await staffToggle.click();
    await expect(staff.getByRole('checkbox').nth(0)).toBeChecked();
    await staff.getByRole('button', { name: 'Clear', exact: true }).click();
    await expect(staffToggle).toContainText('All');
    await page.keyboard.press('Escape');
    await expect(page.locator(modal)).toBeEmpty();
    expect(new URL(page.url()).searchParams.getAll('staffFilterIds').sort()).toEqual([first, second].sort());

    const closeShelf = page.getByRole('button', { name: 'Close Timesheet tools', exact: true });
    if (await closeShelf.isVisible()) await closeShelf.click();
    const previousAnchor = new URL(page.url()).searchParams.get('anchorDate');
    await page.getByRole('link', { name: '>', exact: true }).click();
    await expect.poll(() => new URL(page.url()).searchParams.get('anchorDate')).not.toBe(previousAnchor);
    await expect(page.locator('#timesheet-filters-button')).toHaveText('Filters · 2');
    expect(new URL(page.url()).searchParams.getAll('staffFilterIds').sort()).toEqual([first, second].sort());
    await openTimesheetSettings(page);
    await page.getByRole('link', { name: 'Clear filters', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Clear filters', exact: true })).toBeDisabled();
    await expect(page).not.toHaveURL(/FilterIds/);
    await page.goBack();
    await expect(page.locator('#timesheet-filters-button')).toHaveText('Filters · 2');
    await page.reload();
    await expect(page.locator('#timesheet-filters-button')).toHaveText('Filters · 2');
    await page.goForward();
    await openTimesheetSettings(page);
    await expect(page.getByRole('button', { name: 'Clear filters', exact: true })).toBeDisabled();
});

test('workers can filter shift types without staff or roster-group controls', async ({ page }) => {
    await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
    await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');
    await openTimesheetFilters(page);
    await expect(page.locator(`${modal} ${sections}`)).toHaveCount(1);
    await expect(page.locator(modal).getByRole('button', { name: 'Shift types', exact: true })).toHaveAttribute('aria-expanded', 'true');
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

test('staff-styled option rows respect padded sticky headers and closed borders', async ({ page, isMobile }, testInfo) => {
    await loginAs(page, 'e2e-admin@example.com', 'test-password-123');
    await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');
    const staff = await openTimesheetFilterSection(page, 'Staff');
    const toggle = staff.getByRole('button', { name: 'Staff', exact: true });
    await expect(staff.getByRole('checkbox').first()).toBeVisible();
    await expect(staff.locator('.accordion-collapse')).toHaveClass(/collapse show/);
    const scrollport = page.locator(`${modal} .modal-body`);
    const restingPadding = await scrollport.evaluate(body => parseFloat(getComputedStyle(body).paddingTop));
    expect(restingPadding).toBeGreaterThan(0);
    await expect.poll(async () => {
        const header = await toggle.boundingBox();
        const body = await scrollport.boundingBox();
        return header === null || body === null ? Infinity : Math.abs(header.y - body.y - restingPadding);
    }).toBeLessThan(3);
    const option = staff.locator('label').first();
    await expect(option).toHaveClass(/app-side-panel-entry/);
    const restingBackground = await option.evaluate(row => getComputedStyle(row).backgroundColor);
    if (isMobile) {
        await option.tap();
        await expect(option.getByRole('checkbox')).toBeChecked();
        await expect(option).toHaveCSS('background-color', restingBackground);
        await expect(option).toHaveCSS('box-shadow', 'none');
    } else {
        await option.hover();
        await expect.poll(() => option.evaluate(row => getComputedStyle(row).backgroundColor)).not.toBe(restingBackground);
        await expect(option).not.toHaveCSS('box-shadow', 'none');
    }
    await page.keyboard.press('Tab');
    await option.getByRole('checkbox').focus();
    await expect(option).not.toHaveCSS('box-shadow', 'none');
    // Expand the local layout fixture without creating customer or database records.
    await staff.locator('.app-filter-section-options').evaluate(body => {
        const option = body.querySelector('label')!;
        for (let i = 0; i < 40; i++) body.append(option.cloneNode(true));
    });
    const movingCard = staff.locator('.accordion-item');
    await expect(movingCard).toHaveCSS('background-color', 'rgba(0, 0, 0, 0)');
    await expect(movingCard).toHaveCSS('background-image', 'none');
    await expect(movingCard).toHaveCSS('box-shadow', 'none');
    await expect(movingCard).toHaveCSS('border-left-width', '0px');
    // Cover the first pixels past the resting gap, not just a fully scrolled list.
    for (const offset of [restingPadding / 2, restingPadding + 2, restingPadding + 8]) {
        await scrollport.evaluate((body, top) => { body.scrollTop = top; }, offset);
        await expect.poll(async () => {
            const header = await toggle.boundingBox();
            const body = await scrollport.boundingBox();
            return header === null || body === null ? Infinity
                : Math.abs(header.y - body.y - restingPadding);
        }).toBeLessThan(2);
    }
    await testInfo.attach('sticky-filter-start', { body: await page.screenshot(), contentType: 'image/png' });
    await scrollport.evaluate(body => { body.scrollTop = 350; });
    await expect.poll(() => scrollport.evaluate(body => body.scrollTop)).toBeGreaterThan(300);
    await expect.poll(async () => {
        const header = await toggle.boundingBox();
        const body = await scrollport.boundingBox();
        return header === null || body === null ? Infinity : Math.abs(header.y - body.y - restingPadding);
    }).toBeLessThan(3);
    await expect(toggle).not.toHaveCSS('border-top-left-radius', '0px');
    await expect.poll(async () => {
        const content = staff.locator('.accordion-collapse');
        const clipTop = await content.evaluate(element => parseFloat(getComputedStyle(element).clipPath.replace('inset(', '')));
        const contentBox = await content.boundingBox();
        const headerBox = await toggle.boundingBox();
        return contentBox !== null && headerBox !== null && clipTop > 0
            ? Math.abs(contentBox.y + clipTop - (headerBox.y + headerBox.height)) : Infinity;
    }).toBeLessThan(1);
    await expect.poll(() => toggle.evaluate(button => {
        const box = button.getBoundingClientRect();
        return button.contains(document.elementFromPoint(box.x + box.width / 2, box.y + 2));
    })).toBe(true);
    await expect(page.getByRole('button', { name: 'Apply', exact: true })).toBeInViewport();
    await testInfo.attach('sticky-filter-options', { body: await page.screenshot(), contentType: 'image/png' });
    await toggle.click();
    await expect(toggle).toHaveAttribute('aria-expanded', 'false');
    await expect(toggle).toHaveCSS('border-bottom-width', '1px');
    await expect.poll(() => toggle.evaluate(button => {
        const style = getComputedStyle(button);
        return style.borderBottomColor === style.borderLeftColor;
    })).toBe(true);
    await expect(staff.getByRole('checkbox').first()).toBeHidden();
    await expect(toggle).toBeInViewport();
    await expect(page.locator(modal).getByRole('button', { name: 'Shift types', exact: true })).toBeInViewport();
});
