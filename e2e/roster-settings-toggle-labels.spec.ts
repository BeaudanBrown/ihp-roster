import { expect, test } from '@playwright/test';
import { E2E_TIMEOUT, openRoster, openRosterSettings, runSql } from './test-helpers';

const managerUserId = 'a0000000-0000-0000-0000-000000000003';

function seedEnabledRosterDisplayPreferences() {
    runSql(`
        INSERT INTO user_preferences (user_id, show_shift_type_highlights, show_wage_estimates)
        VALUES ('${managerUserId}', FALSE, TRUE)
        ON CONFLICT (user_id) DO UPDATE SET
            show_shift_type_highlights = FALSE,
            show_wage_estimates = TRUE,
            updated_at = NOW();
    `);
}

test.describe('Roster settings toggle labels', () => {
    test.describe.configure({ retries: 0, timeout: E2E_TIMEOUT.test });

    test('keeps visible labels, accessibility state, and the selected tab synchronized', async ({ page }) => {
        seedEnabledRosterDisplayPreferences();
        await openRoster(page, { email: 'e2e-admin@example.com', ensureEditable: false });
        await openRosterSettings(page);

        const settingsPanel = page.locator('#roster-staff-panel-fragment');
        const settingsTab = page.getByRole('tab', { name: 'Settings', exact: true });
        const warningButton = settingsPanel.locator('label[for="show-roster-warnings"]');
        const wageButton = settingsPanel.locator('label[for="show-wage-estimates"]');

        await expect(warningButton).toContainText('Warnings enabled');
        await warningButton.click();
        await expect(warningButton).toContainText('Warnings disabled');
        await expect(warningButton).toHaveAttribute('aria-pressed', 'false');
        await expect(warningButton).toHaveClass(/btn-outline-success/);
        await expect(page.locator('#roster-staff-panel-settings-pane')).toBeVisible();
        await expect(settingsTab).toHaveAttribute('aria-selected', 'true');

        await warningButton.click();
        await expect(warningButton).toContainText('Warnings enabled');
        await expect(warningButton).toHaveAttribute('aria-pressed', 'true');
        await expect(warningButton).toHaveClass(/btn-success/);

        await expect(wageButton).toContainText('Wages enabled');
        await wageButton.click();
        await expect(wageButton).toContainText('Wages disabled');
        await expect(wageButton).toHaveAttribute('aria-pressed', 'false');
        await expect(wageButton).toHaveClass(/btn-outline-success/);
        await expect(page.locator('#roster-staff-panel-settings-pane')).toBeVisible();
        await expect(settingsTab).toHaveAttribute('aria-selected', 'true');

        await wageButton.click();
        await expect(wageButton).toContainText('Wages enabled');
        await expect(wageButton).toHaveAttribute('aria-pressed', 'true');
        await expect(wageButton).toHaveClass(/btn-success/);
        await expect(settingsTab).toHaveAttribute('aria-selected', 'true');
    });

    test('returns an unsaved optimistic label to server state on the next authoritative render', async ({ page }) => {
        seedEnabledRosterDisplayPreferences();
        await openRoster(page, { email: 'e2e-admin@example.com', ensureEditable: false });
        await openRosterSettings(page);

        const warningButton = page.locator('label[for="show-roster-warnings"]');
        await expect(warningButton).toContainText('Warnings enabled');

        await page.route('**/UpdateRosterWarningPreference**', async (route) => route.abort());
        await warningButton.click();
        await expect(warningButton).toContainText('Warnings disabled');
        await page.unroute('**/UpdateRosterWarningPreference**');

        await page.reload();
        await expect(page.locator('.roster-grid-frame')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await openRosterSettings(page);
        await expect(warningButton).toContainText('Warnings enabled');
        await expect(warningButton).toHaveAttribute('aria-pressed', 'true');
    });
});
