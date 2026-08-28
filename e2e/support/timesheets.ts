import { expect, type Page } from '@playwright/test';
import { runSql, sqlString } from './database';

export function resetTimesheetDisplayPreferences(email: string) {
    runSql(`
        INSERT INTO user_preferences (user_id, hide_approved, show_timesheet_suggestions, show_timesheet_wage_estimates, timesheet_preferences_initialized_at)
        SELECT id, FALSE, TRUE, TRUE, NOW() FROM users WHERE email = ${sqlString(email)}
        ON CONFLICT (user_id) DO UPDATE SET
            hide_approved = FALSE,
            show_timesheet_suggestions = TRUE,
            show_timesheet_wage_estimates = TRUE,
            timesheet_preferences_initialized_at = NOW(),
            updated_at = NOW();
    `);
}

export async function openTimesheetSettings(page: Page) {
    const settingsTab = page.getByRole('tab', { name: 'Settings' });
    if (await settingsTab.count()) await settingsTab.click();
    await expect(page.locator('#timesheet-side-panel-content')).toContainText('Hide approved');
}
