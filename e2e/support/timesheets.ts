import { expect, type Page } from '@playwright/test';
import { E2E_TIMEOUT } from '../timeouts';
import { runSql, sqlString } from './database';
import { waitForLiveRecovery } from './runtime';

export function resetTimesheetDisplayPreferences(emails: string | string[]) {
    const targetEmails = typeof emails === 'string' ? [emails] : emails;
    if (targetEmails.length === 0) return;
    runSql(`
        INSERT INTO user_preferences (user_id, hide_approved, show_timesheet_suggestions, show_timesheet_wage_estimates, timesheet_wage_display_mode, timesheet_preferences_initialized_at)
        SELECT id, FALSE, TRUE, TRUE, 'visible_and_all_timesheets', NOW() FROM users WHERE email IN (${targetEmails.map(sqlString).join(', ')})
        ON CONFLICT (user_id) DO UPDATE SET
            hide_approved = FALSE,
            show_timesheet_suggestions = TRUE,
            show_timesheet_wage_estimates = TRUE,
            timesheet_wage_display_mode = 'visible_and_all_timesheets',
            timesheet_preferences_initialized_at = NOW(),
            updated_at = NOW();
    `);
}

export async function chooseBlankTimesheet(page: Page, preferredStaffName = 'E2E Manager') {
    const createForm = page.locator('#timesheet-entry-create-form');
    const blankChoice = page.getByRole('link', { name: 'Use blank timesheet' }).first();
    await Promise.race([
        createForm.waitFor({ state: 'visible', timeout: E2E_TIMEOUT.action }),
        blankChoice.waitFor({ state: 'visible', timeout: E2E_TIMEOUT.action }).then(async () => {
            const preferredChoice = page.locator('article', { hasText: preferredStaffName }).getByRole('link', { name: 'Use blank timesheet' }).first();
            await (await preferredChoice.count() ? preferredChoice : blankChoice).click();
        }),
    ]);
    await expect(createForm).toBeVisible({ timeout: E2E_TIMEOUT.action });
}

export async function openTimesheetSettings(page: Page) {
    await waitForLiveRecovery(page, E2E_TIMEOUT.liveUpdate);
    const settingsTab = page.getByRole('tab', { name: 'Settings' });
    if (!(await settingsTab.isVisible())) {
        const mobilePanelToggle = page.getByRole('button', { name: 'Open Timesheet tools' });
        if (await mobilePanelToggle.isVisible()) await mobilePanelToggle.click();
    }
    if (await settingsTab.count()) {
        await expect.poll(async () => {
            if (!(await settingsTab.isVisible())) {
                const mobilePanelToggle = page.getByRole('button', { name: 'Open Timesheet tools' });
                if (await mobilePanelToggle.isVisible()) await mobilePanelToggle.click();
            }
            const showApproved = page.getByRole('switch', { name: 'Show approved' });
            if ((await settingsTab.getAttribute('aria-selected')) !== 'true') {
                await settingsTab.click().catch(() => {});
            }
            return showApproved.isVisible();
        }, { timeout: E2E_TIMEOUT.liveUpdate }).toBe(true);
    }
}
