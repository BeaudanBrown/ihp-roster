import { expect, test, type Locator, type Page } from '@playwright/test';
import { dialogOverlayMountDomId } from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from './timeouts';
import {
    addRowToRosterDay,
    editableRosterRows,
    existingRosterShiftLaunchers,
    openRoster,
    openRosterShiftDialog,
    rosterDaySections,
    saveRosterShiftDialog,
} from './test-helpers';

const dialogSelector = `#${dialogOverlayMountDomId}`;
const millisecondsPerWeek = 7 * 24 * 60 * 60 * 1000;

function weekOffsetFromCurrentMonday(targetMonday: string) {
    const now = new Date();
    const todayUtc = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
    const currentMondayUtc = todayUtc - ((now.getUTCDay() + 6) % 7) * 24 * 60 * 60 * 1000;
    return Math.round((Date.parse(`${targetMonday}T00:00:00Z`) - currentMondayUtc) / millisecondsPerWeek);
}

function saturdaySection(page: Page) {
    return rosterDaySections(page).nth(5);
}

async function firstNonEmptyOption(select: Locator) {
    return select.locator('option').evaluateAll((options) =>
        options
            .map((option) => (option instanceof HTMLOptionElement ? option.value : ''))
            .find((value) => value !== '') ?? '',
    );
}

async function fillBoundaryShift(page: Page, startTime: string, endTime: string) {
    const staffSelect = page.locator('#roster-shift-staff-id');
    const shiftTypeSelect = page.locator('#roster-shift-type-id');
    await staffSelect.selectOption(await firstNonEmptyOption(staffSelect));
    await shiftTypeSelect.selectOption(await firstNonEmptyOption(shiftTypeSelect));
    await page.locator('input[name="startTime"]').evaluate((input, value) => {
        const field = input as HTMLInputElement;
        field.value = value;
        field.dispatchEvent(new Event('input', { bubbles: true }));
        field.dispatchEvent(new Event('change', { bubbles: true }));
    }, startTime);
    await page.locator('input[name="endTime"]').evaluate((input, value) => {
        const field = input as HTMLInputElement;
        field.value = value;
        field.dispatchEvent(new Event('input', { bubbles: true }));
        field.dispatchEvent(new Event('change', { bubbles: true }));
    }, endTime);
}

async function submitRosterShift(page: Page) {
    const responsePromise = page.waitForResponse((response) =>
        response.request().method() === 'POST' && response.url().includes('/CreateRosterSlot'),
    );
    await page.getByRole('button', { name: 'Save' }).click();
    const response = await responsePromise;
    expect(response.status(), await response.text()).toBe(200);
}

async function openFreshSaturdayShift(page: Page, targetMonday: string) {
    await openRoster(page, {
        weekOffset: weekOffsetFromCurrentMonday(targetMonday),
        maxWeekAdvances: 0,
    });
    await expect(saturdaySection(page)).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
    await addRowToRosterDay(saturdaySection(page));
    const row = editableRosterRows(saturdaySection(page)).last();
    await openRosterShiftDialog(page, row.locator('[data-roster-shift-launcher="true"]').first());
}

test.describe('DST time boundaries', () => {
    test.setTimeout(E2E_TIMEOUT.slowTest);

    test('shows an occurrence chooser only for the repeated autumn roster time', async ({ page }) => {
        await openFreshSaturdayShift(page, '2026-03-30');
        await fillBoundaryShift(page, '02:30', '04:00');
        await expect(page.locator('[data-time-occurrence-chooser]')).toHaveCount(0);

        await submitRosterShift(page);

        const startChooser = page.locator('[data-time-occurrence-chooser="startOccurrence"]');
        await expect(startChooser).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(startChooser).toContainText('Choose occurrence');
        await expect(page.locator('[data-time-occurrence-chooser="endOccurrence"]')).toHaveCount(0);
        await expect(page.locator(dialogSelector)).toContainText('Choose whether this is the first or second occurrence.');

        await startChooser.locator('select').selectOption('second');
        await saveRosterShiftDialog(page);

        const createdLauncher = existingRosterShiftLaunchers(saturdaySection(page)).last();
        await openRosterShiftDialog(page, createdLauncher);
        await expect(page.locator('[data-time-occurrence-chooser="startOccurrence"] select')).toHaveValue('second');
        await expect(page.locator('[data-time-occurrence-chooser="endOccurrence"]')).toHaveCount(0);
    });

    test('rejects the nonexistent spring roster time without showing an occurrence chooser', async ({ page }) => {
        await openFreshSaturdayShift(page, '2026-09-28');
        await fillBoundaryShift(page, '02:30', '04:00');

        await submitRosterShift(page);

        await expect(page.locator(dialogSelector)).toContainText(
            'This local time does not exist because clocks move forward.',
            { timeout: E2E_TIMEOUT.assertion },
        );
        await expect(page.locator('[data-time-occurrence-chooser]')).toHaveCount(0);
        await expect(existingRosterShiftLaunchers(saturdaySection(page))).toHaveCount(0);
    });
});
