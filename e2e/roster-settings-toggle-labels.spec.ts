import { expect, test, type Locator, type Page } from '@playwright/test';
import { toggleInputDomAttr, toggleLabelStateDomAttr } from '../frontend/ts/generated/contracts';
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

function visibleToggleLabel(button: Locator) {
    return button.locator(`[${toggleLabelStateDomAttr}]:not([hidden])`);
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

        await expect(visibleToggleLabel(warningButton)).toHaveText('Warnings enabled');
        await clickToggleAndWait(page, warningButton, 'UpdateRosterWarningPreference');
        await expect(visibleToggleLabel(warningButton)).toHaveText('Warnings disabled');
        await expect(warningButton.locator(`[${toggleInputDomAttr}]`)).not.toBeChecked();
        await expect(warningButton).toHaveAttribute('aria-pressed', 'false');
        await expect(warningButton).not.toHaveClass(/is-toggle-checked/);
        await expect(page.locator('#roster-staff-panel-settings-pane')).toBeVisible();
        await expect(settingsTab).toHaveAttribute('aria-selected', 'true');

        await clickToggleAndWait(page, warningButton, 'UpdateRosterWarningPreference');
        await expect(visibleToggleLabel(warningButton)).toHaveText('Warnings enabled');
        await expect(warningButton.locator(`[${toggleInputDomAttr}]`)).toBeChecked();
        await expect(warningButton).toHaveAttribute('aria-pressed', 'true');
        await expect(warningButton).toHaveClass(/is-toggle-checked/);

        await expect(visibleToggleLabel(wageButton)).toHaveText('Wages enabled');
        await clickToggleAndWait(page, wageButton, 'UpdateRosterWageEstimatePreference');
        await expect(visibleToggleLabel(wageButton)).toHaveText('Wages disabled');
        await expect(wageButton.locator(`[${toggleInputDomAttr}]`)).not.toBeChecked();
        await expect(wageButton).toHaveAttribute('aria-pressed', 'false');
        await expect(wageButton).not.toHaveClass(/is-toggle-checked/);
        await expect(page.locator('#roster-staff-panel-settings-pane')).toBeVisible();
        await expect(settingsTab).toHaveAttribute('aria-selected', 'true');

        await clickToggleAndWait(page, wageButton, 'UpdateRosterWageEstimatePreference');
        await expect(visibleToggleLabel(wageButton)).toHaveText('Wages enabled');
        await expect(wageButton.locator(`[${toggleInputDomAttr}]`)).toBeChecked();
        await expect(wageButton).toHaveAttribute('aria-pressed', 'true');
        await expect(wageButton).toHaveClass(/is-toggle-checked/);
        await expect(settingsTab).toHaveAttribute('aria-selected', 'true');
    });

    test('returns an unsaved optimistic label to server state on the next authoritative render', async ({ page }) => {
        seedEnabledRosterDisplayPreferences();
        await openRoster(page, { email: 'e2e-admin@example.com', ensureEditable: false });
        await openRosterSettings(page);

        const warningButton = page.locator('label[for="show-roster-warnings"]');
        await expect(visibleToggleLabel(warningButton)).toHaveText('Warnings enabled');

        await page.route('**/UpdateRosterWarningPreference**', async (route) => route.abort());
        await warningButton.click();
        await expect(visibleToggleLabel(warningButton)).toHaveText('Warnings disabled');
        await page.unroute('**/UpdateRosterWarningPreference**');

        await page.reload();
        await expect(page.locator('.roster-grid-frame')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await openRosterSettings(page);
        await expect(visibleToggleLabel(warningButton)).toHaveText('Warnings enabled');
        await expect(warningButton).toHaveAttribute('aria-pressed', 'true');
    });
});
