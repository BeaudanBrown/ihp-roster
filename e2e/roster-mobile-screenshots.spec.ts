import { test, expect } from '@playwright/test';
import { addRowToFirstRosterDay, openRoster } from './test-helpers';
import { attachRosterMobileDiagnostics, expectRosterMobileLayoutStable } from './roster-mobile-diagnostics';

test.describe('Roster mobile screenshots', () => {
    test('captures the main roster mobile states for visual review', async ({ page }, testInfo) => {
        await openRoster(page);
        await expect(page.locator('#roster-week-shell')).toBeVisible();
        await expectRosterMobileLayoutStable(page);
        await attachRosterMobileDiagnostics(page, testInfo, 'initial');

        await addRowToFirstRosterDay(page);
        await expect(page.locator('[data-roster-row]:has(select[name="staffId"])').first()).toBeVisible();
        await expectRosterMobileLayoutStable(page);
        await attachRosterMobileDiagnostics(page, testInfo, 'after-add-row');

        const firstTimeField = page.locator('[data-time-picker-field]').first();
        await firstTimeField.scrollIntoViewIfNeeded();
        await firstTimeField.click();
        await expectRosterMobileLayoutStable(page);
        await attachRosterMobileDiagnostics(page, testInfo, 'after-time-field-focus');

        const firstStaffSelect = page.locator('.slot-staff-input').first();
        await firstStaffSelect.scrollIntoViewIfNeeded();
        await firstStaffSelect.focus();
        await expectRosterMobileLayoutStable(page);
        await attachRosterMobileDiagnostics(page, testInfo, 'after-staff-select-focus');
    });
});
