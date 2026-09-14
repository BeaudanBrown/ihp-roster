import { test, expect } from '@playwright/test';
import { gotoWhenReady } from './support/runtime';
import { loginAs } from './support/session';
import { openRoster, openRosterSettings } from './support/roster';
import { resetTimesheetDisplayPreferences } from './support/timesheets';
import { runSql } from './support/database';

type ToolbarMetrics = {
    quickTop: number;
    quickBottom: number;
    quickCenterX: number;
    navigationTop: number;
    navigationBottom: number;
    navigationCenterX: number;
    settingsTop: number;
    settingsRight: number;
    auxiliaryTop: number | null;
    auxiliaryRight: number | null;
    resetTop: number | null;
    resetBottom: number | null;
    resetCenterX: number | null;
    toolbarCenterX: number;
    toolbarRight: number;
};

async function weekToolbarMetrics(page: import('@playwright/test').Page, toolbarSelector: string): Promise<ToolbarMetrics> {
    return page.locator(toolbarSelector).evaluate((toolbar) => {
        if (!(toolbar instanceof HTMLElement)) {
            throw new Error('Expected toolbar to be an HTMLElement');
        }

        const rectFor = (selector: string) => {
            const element = toolbar.querySelector(selector);
            if (!(element instanceof HTMLElement)) {
                throw new Error(`Expected toolbar section ${selector}`);
            }
            return element.getBoundingClientRect();
        };

        const visibleRectFor = (selector: string) => {
            const elements = Array.from(toolbar.querySelectorAll(selector));
            const element = elements.find((candidate): candidate is HTMLElement => {
                if (!(candidate instanceof HTMLElement)) return false;
                const style = getComputedStyle(candidate);
                const rect = candidate.getBoundingClientRect();
                return style.display !== 'none' && rect.width > 0 && rect.height > 0;
            });
            return element?.getBoundingClientRect() ?? null;
        };

        const quick = rectFor('[data-week-toolbar-section="quick"]');
        const navigation = rectFor('[data-week-toolbar-section="navigation"]');
        const settings = visibleRectFor('[data-week-toolbar-section="settings"] button, [data-week-toolbar-section="settings"] a')
            ?? rectFor('[data-week-toolbar-section="settings"]');
        const auxiliary = visibleRectFor('[data-week-toolbar-section^="auxiliary"]');
        const reset = visibleRectFor('[data-week-toolbar-section="reset"] .app-week-nav-button');
        const toolbarRect = toolbar.getBoundingClientRect();

        return {
            quickTop: Math.round(quick.top),
            quickBottom: Math.round(quick.bottom),
            quickCenterX: Math.round(quick.left + quick.width / 2),
            navigationTop: Math.round(navigation.top),
            navigationBottom: Math.round(navigation.bottom),
            navigationCenterX: Math.round(navigation.left + navigation.width / 2),
            settingsTop: Math.round(settings.top),
            settingsRight: Math.round(settings.right),
            auxiliaryTop: auxiliary ? Math.round(auxiliary.top) : null,
            auxiliaryRight: auxiliary ? Math.round(auxiliary.right) : null,
            resetTop: reset ? Math.round(reset.top) : null,
            resetBottom: reset ? Math.round(reset.bottom) : null,
            resetCenterX: reset ? Math.round(reset.left + reset.width / 2) : null,
            toolbarCenterX: Math.round(toolbarRect.left + toolbarRect.width / 2),
            toolbarRight: Math.round(toolbarRect.right),
        };
    });
}

test.describe('Shared week toolbar responsive layout', () => {
    test('spaces roster week action buttons evenly in the staff panel settings tab', async ({ page }) => {
        test.setTimeout(90_000);
        await page.setViewportSize({ width: 1280, height: 900 });

        await openRoster(page, { email: 'e2e-admin@example.com', ensureEditable: true });
        await openRosterSettings(page);

        const actionGroup = page.locator('.roster-week-action-grid');
        await expect(actionGroup).toBeVisible();
        await expect(actionGroup.getByRole('button', { name: 'Sort shifts' })).toBeVisible();
        await expect(actionGroup.getByRole('button', { name: 'Copy Previous Week' })).toBeVisible();

        const metrics = await actionGroup.evaluate((group) => {
            const groupElement = group as HTMLElement;
            const groupRect = groupElement.getBoundingClientRect();
            const buttons = Array.from(groupElement.querySelectorAll('button')) as HTMLElement[];
            return {
                display: window.getComputedStyle(groupElement).display,
                groupLeft: groupRect.left,
                groupWidth: groupRect.width,
                buttons: buttons.map((button) => {
                    const rect = button.getBoundingClientRect();
                    const style = window.getComputedStyle(button);
                    return {
                        width: rect.width,
                        centerX: rect.left + rect.width / 2,
                        justifyContent: style.justifyContent,
                        textAlign: style.textAlign,
                    };
                }),
            };
        });

        expect(metrics.display).toBe('grid');
        expect(metrics.buttons).toHaveLength(2);
        expect(Math.abs(metrics.buttons[0].width - metrics.buttons[1].width)).toBeLessThanOrEqual(1);
        expect(Math.abs(metrics.buttons[0].centerX - (metrics.groupLeft + metrics.groupWidth * 0.25))).toBeLessThanOrEqual(2);
        expect(Math.abs(metrics.buttons[1].centerX - (metrics.groupLeft + metrics.groupWidth * 0.75))).toBeLessThanOrEqual(2);
        for (const button of metrics.buttons) {
            expect(button.justifyContent).toBe('center');
            expect(button.textAlign).toBe('center');
        }
    });

    test('keeps roster and timesheet week controls on one desktop row', async ({ page }) => {
        test.setTimeout(90_000);
        await page.setViewportSize({ width: 1280, height: 900 });
        runSql("UPDATE venue_config SET roster_end_times_enabled = TRUE WHERE venue_id = 'a1000000-0000-0000-0000-000000000001'");

        await openRoster(page, { email: 'e2e-admin@example.com', ensureEditable: false });
        const roster = await weekToolbarMetrics(page, '[data-week-toolbar="roster"]');
        expect(Math.abs(roster.quickTop - roster.navigationTop)).toBeLessThanOrEqual(2);
        expect(Math.abs(roster.settingsTop - roster.navigationTop)).toBeLessThanOrEqual(2);
        if (roster.auxiliaryRight !== null) {
            expect(roster.auxiliaryRight).toBeGreaterThan(roster.toolbarCenterX);
        }

        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');
        const timesheets = await weekToolbarMetrics(page, '[data-week-toolbar="timesheets"]');
        expect(Math.abs(timesheets.quickTop - timesheets.navigationTop)).toBeLessThanOrEqual(2);
        expect(timesheets.settingsTop).toBeGreaterThanOrEqual(timesheets.navigationTop);
        expect(timesheets.settingsTop).toBeLessThanOrEqual(timesheets.navigationBottom);
    });

    test('orders roster mobile controls as quick actions, navigation, wage summary', async ({ page }) => {
        test.setTimeout(90_000);
        await page.setViewportSize({ width: 390, height: 844 });
        runSql("UPDATE venue_config SET roster_end_times_enabled = TRUE WHERE venue_id = 'a1000000-0000-0000-0000-000000000001'");

        await openRoster(page, { email: 'e2e-admin@example.com', ensureEditable: false });
        const toolbar = page.locator('[data-week-toolbar="roster"]');
        await expect(toolbar.locator('[data-week-toolbar-section="primary"]').getByText('Published')).toBeVisible();
        await expect(toolbar.getByRole('link', { name: 'This week' })).toBeVisible();
        await expect(toolbar.getByRole('button', { name: 'Roster settings' })).toHaveCount(0);
        await expect(page.getByRole('tab', { name: 'Settings', exact: true })).toBeVisible();
        await expect(toolbar.locator('.roster-week-nav-group')).toBeVisible();
        if ((await toolbar.locator('[data-week-toolbar-section="auxiliary"] .roster-wage-summary').count()) > 0) {
            await expect(toolbar.locator('[data-week-toolbar-section="auxiliary"] .roster-wage-summary')).toBeVisible();
        }

        const metrics = await weekToolbarMetrics(page, '[data-week-toolbar="roster"]');
        expect(metrics.resetCenterX).not.toBeNull();
        expect(Math.abs((metrics.resetCenterX ?? 0) - metrics.toolbarCenterX)).toBeLessThanOrEqual(4);
        expect(metrics.settingsRight).toBeLessThanOrEqual(metrics.toolbarRight - 8);
        expect(metrics.resetBottom).not.toBeNull();
        expect(metrics.navigationTop).toBeGreaterThanOrEqual((metrics.resetBottom ?? 0) - 1);
        if (metrics.auxiliaryTop !== null) {
            expect(metrics.auxiliaryTop).toBeGreaterThanOrEqual(metrics.navigationBottom - 1);
        }
    });

    test('centres Timesheets mobile reset above week navigation with the Settings panel stacked below', async ({ page }) => {
        test.setTimeout(90_000);
        await page.setViewportSize({ width: 390, height: 844 });
        resetTimesheetDisplayPreferences('e2e-admin@example.com');
        await loginAs(page, 'e2e-admin@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');

        const toolbar = page.locator('[data-week-toolbar="timesheets"]');
        await expect(toolbar.getByRole('link', { name: 'This week' })).toBeVisible();
        await expect(toolbar.getByRole('button', { name: 'Expand main content' })).toBeHidden();
        await expect(toolbar.locator('.app-week-nav-group')).toBeVisible();
        await expect(toolbar.locator('.timesheet-wage-summary')).toBeVisible();
        await expect(page.getByRole('tab', { name: 'Settings' })).toBeVisible();

        const metrics = await weekToolbarMetrics(page, '[data-week-toolbar="timesheets"]');
        expect(metrics.resetCenterX).not.toBeNull();
        expect(Math.abs((metrics.resetCenterX ?? 0) - metrics.toolbarCenterX)).toBeLessThanOrEqual(4);
        expect(metrics.resetBottom).not.toBeNull();
        expect(metrics.navigationTop).toBeGreaterThanOrEqual((metrics.resetBottom ?? 0) - 1);
        expect(metrics.auxiliaryTop).not.toBeNull();
        expect(metrics.auxiliaryTop ?? 0).toBeGreaterThanOrEqual(metrics.navigationBottom - 1);
    });
});
