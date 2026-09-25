import { expect, test, type Locator, type Page } from '@playwright/test';
import { toggleInputDomAttr } from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from './timeouts';
import { openRoster, openRosterSettings } from './support/roster';
import { runSql } from './support/database';

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

async function clickToggleAndWait(page: Page, button: Locator, actionPath: string) {
    const beforeRequestMarker = 'data-e2e-before-toggle-request';
    await button.evaluate((element, marker) => element.setAttribute(marker, 'true'), beforeRequestMarker);
    const responsePromise = page.waitForResponse((response) =>
        response.request().method() === 'POST' && new URL(response.url()).pathname.includes(actionPath),
    );
    await button.click();
    expect((await responsePromise).ok()).toBe(true);
    await expect(button).not.toHaveAttribute(beforeRequestMarker, 'true');
}

function toggleLabel(button: Locator) {
    return button.locator('.app-toggle-button-label');
}

test.describe('Roster settings toggle labels', () => {
    test.describe.configure({ retries: 0, timeout: E2E_TIMEOUT.test });

    test('keeps visible labels, accessibility state, and the selected tab synchronized', async ({ page }) => {
        seedEnabledRosterDisplayPreferences();
        await openRoster(page, { email: 'e2e-admin@example.com', ensureEditable: false });
        await openRosterSettings(page);

        const settingsTab = page.getByRole('tab', { name: 'Settings', exact: true });
        const warningButton = page.locator('label[for="show-roster-warnings"]');
        const wageButton = page.locator('label[for="show-wage-estimates"]');
        const settingsPane = page.locator('#roster-staff-panel-settings-pane');

        await expect(settingsPane).not.toHaveClass(/\bfade\b/);
        await expect(toggleLabel(warningButton)).toHaveText('Show roster warnings');
        await clickToggleAndWait(page, warningButton, 'UpdateRosterWarningPreference');
        await expect(toggleLabel(warningButton)).toHaveText('Show roster warnings');
        await expect(warningButton.locator(`[${toggleInputDomAttr}]`)).not.toBeChecked();
        await expect(warningButton).toHaveAttribute('aria-pressed', 'false');
        await expect(settingsPane).toBeVisible();
        await expect(settingsPane).not.toHaveClass(/\bfade\b/);
        await expect(settingsTab).toHaveAttribute('aria-selected', 'true');

        await clickToggleAndWait(page, warningButton, 'UpdateRosterWarningPreference');
        await expect(toggleLabel(warningButton)).toHaveText('Show roster warnings');
        await expect(warningButton.locator(`[${toggleInputDomAttr}]`)).toBeChecked();
        await expect(warningButton).toHaveAttribute('aria-pressed', 'true');

        await expect(toggleLabel(wageButton)).toHaveText('Show expected wage estimates');
        await clickToggleAndWait(page, wageButton, 'UpdateRosterWageEstimatePreference');
        await expect(toggleLabel(wageButton)).toHaveText('Show expected wage estimates');
        await expect(wageButton.locator(`[${toggleInputDomAttr}]`)).not.toBeChecked();
        await expect(wageButton).toHaveAttribute('aria-pressed', 'false');
        await expect(settingsPane).toBeVisible();
        await expect(settingsPane).not.toHaveClass(/\bfade\b/);
        await expect(settingsTab).toHaveAttribute('aria-selected', 'true');

        await clickToggleAndWait(page, wageButton, 'UpdateRosterWageEstimatePreference');
        await expect(toggleLabel(wageButton)).toHaveText('Show expected wage estimates');
        await expect(wageButton.locator(`[${toggleInputDomAttr}]`)).toBeChecked();
        await expect(wageButton).toHaveAttribute('aria-pressed', 'true');
        await expect(settingsTab).toHaveAttribute('aria-selected', 'true');
    });

    test('returns an unsaved optimistic label to server state on the next authoritative render', async ({ page }) => {
        seedEnabledRosterDisplayPreferences();
        await openRoster(page, { email: 'e2e-admin@example.com', ensureEditable: false });
        await openRosterSettings(page);

        const warningButton = page.locator('label[for="show-roster-warnings"]');
        await expect(toggleLabel(warningButton)).toHaveText('Show roster warnings');

        await page.route('**/UpdateRosterWarningPreference**', async (route) => route.abort());
        await warningButton.click();
        await expect(warningButton.locator(`[${toggleInputDomAttr}]`)).not.toBeChecked();
        await page.unroute('**/UpdateRosterWarningPreference**');

        await page.reload();
        await expect(page.locator('.roster-grid-frame')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await openRosterSettings(page);
        await expect(toggleLabel(warningButton)).toHaveText('Show roster warnings');
        await expect(warningButton).toHaveAttribute('aria-pressed', 'true');
    });
});
