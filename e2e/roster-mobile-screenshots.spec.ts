import { test, expect } from '@playwright/test';
import { dialogMountDomAttr, dialogOverlayMountDomId } from '../frontend/ts/generated/contracts';
import { addRowToFirstRosterDay, openRoster } from './test-helpers';
import { attachRosterMobileDiagnostics, expectRosterMobileLayoutStable } from './roster-mobile-diagnostics';

test.describe('Roster mobile screenshots', () => {
    test('captures the main roster mobile states for visual review', async ({ page }, testInfo) => {
        await openRoster(page);
        await expect(page.locator('#roster-week-shell')).toBeVisible();
        await expectRosterMobileLayoutStable(page);
        await attachRosterMobileDiagnostics(page, testInfo, 'initial');

        await addRowToFirstRosterDay(page);
        await expect(page.locator('[data-roster-row]:has([data-roster-shift-launcher="true"])').first()).toBeVisible();
        await expectRosterMobileLayoutStable(page);
        await attachRosterMobileDiagnostics(page, testInfo, 'after-add-row');

        const firstLauncher = page.locator('[data-roster-shift-launcher="true"]').first();
        await firstLauncher.scrollIntoViewIfNeeded();
        await firstLauncher.focus();
        await expectRosterMobileLayoutStable(page);
        await attachRosterMobileDiagnostics(page, testInfo, 'after-launcher-focus');

        await firstLauncher.click();
        await expect(page.locator(`#${dialogOverlayMountDomId} [${dialogMountDomAttr}]`)).toBeVisible();
        await expectRosterMobileLayoutStable(page);
        await attachRosterMobileDiagnostics(page, testInfo, 'after-shift-dialog-open');
    });
});
