import { expect, test, type Locator, type Page } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { openRoster, openRosterSettings } from './support/roster';
import { runSql } from './support/database';

const managerUserId = 'a0000000-0000-0000-0000-000000000003';

function seedEnabledRosterDisplayPreferences() {
    runSql(`
        INSERT INTO user_preferences (user_id, show_shift_type_highlights, show_wage_estimates, roster_pay_display_mode)
        VALUES ('${managerUserId}', FALSE, TRUE, 'roster_pay_daily')
        ON CONFLICT (user_id) DO UPDATE SET
            show_shift_type_highlights = FALSE,
            show_wage_estimates = TRUE,
            roster_pay_display_mode = 'roster_pay_daily',
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

test.describe('Roster settings toggle labels', () => {
    test.describe.configure({ retries: 0, timeout: E2E_TIMEOUT.test });

    test('keeps visible labels, accessibility state, and the selected tab synchronized', async ({ page }) => {
        seedEnabledRosterDisplayPreferences();
        await openRoster(page, { email: 'e2e-admin@example.com', ensureEditable: false });
        await openRosterSettings(page);

        const settingsTab = page.getByRole('tab', { name: 'Settings', exact: true });
        const settingsPane = page.getByRole('tabpanel', { name: 'Settings', exact: true });
        const warningButton = settingsPane.locator('label[for="show-roster-warnings"]');
        const warningSwitch = settingsPane.getByRole('switch', { name: 'Show roster warnings', exact: true });
        const payMode = settingsPane.getByRole('combobox', { name: 'Expected wages', exact: true });

        await expect(settingsPane).not.toHaveClass(/\bfade\b/);
        await expect(warningButton).toHaveText('Show roster warnings');
        await expect(warningSwitch).toBeChecked();
        await clickToggleAndWait(page, warningButton, 'UpdateRosterWarningPreference');
        await expect(warningButton).toHaveText('Show roster warnings');
        await expect(warningSwitch).not.toBeChecked();
        await expect(warningSwitch).toHaveAttribute('aria-checked', 'false');
        await expect(settingsPane).toBeVisible();
        await expect(settingsPane).not.toHaveClass(/\bfade\b/);
        await expect(settingsTab).toHaveAttribute('aria-selected', 'true');

        await clickToggleAndWait(page, warningButton, 'UpdateRosterWarningPreference');
        await expect(warningButton).toHaveText('Show roster warnings');
        await expect(warningSwitch).toBeChecked();
        await expect(warningSwitch).toHaveAttribute('aria-checked', 'true');

        await expect(payMode).toHaveValue('roster_pay_daily');
        await expect(payMode.locator('option')).toHaveText(['Hidden', 'Total only', 'Daily + total']);
        for (const mode of ['roster_pay_hidden', 'roster_pay_total', 'roster_pay_daily']) {
            const marker = 'data-e2e-before-pay-save';
            await payMode.evaluate((element, attribute) => element.setAttribute(attribute, 'true'), marker);
            const saved = page.waitForResponse((response) =>
                response.request().method() === 'POST'
                && new URL(response.url()).pathname.includes('UpdateRosterWageEstimatePreference'),
            );
            await payMode.selectOption(mode);
            expect((await saved).ok()).toBe(true);
            await expect(payMode).not.toHaveAttribute(marker, 'true');
            await expect(payMode).toHaveValue(mode);
            await expect(settingsPane).toBeVisible();
            await expect(settingsTab).toHaveAttribute('aria-selected', 'true');
            await expect(page.locator('.roster-wage-summary-total')).toHaveCount(mode === 'roster_pay_hidden' ? 0 : 1);
            if (mode !== 'roster_pay_daily') {
                await expect(page.locator('.roster-day-wage-total')).toHaveCount(0);
                await expect(page.locator('.roster-grid-frame')).toHaveAttribute('data-roster-wages', 'hidden');
            } else {
                await expect(page.locator('.roster-day-wage-total').first()).toBeAttached();
            }
        }
        await page.reload();
        await openRosterSettings(page);
        await expect(payMode).toHaveValue('roster_pay_daily');
    });

    test('returns unsaved optimistic switch state to server state on the next authoritative render', async ({ page }) => {
        seedEnabledRosterDisplayPreferences();
        await openRoster(page, { email: 'e2e-admin@example.com', ensureEditable: false });
        await openRosterSettings(page);

        const warningButton = page.locator('label[for="show-roster-warnings"]');
        const warningSwitch = page.getByRole('switch', { name: 'Show roster warnings', exact: true });
        await expect(warningButton).toHaveText('Show roster warnings');
        await expect(warningSwitch).toBeChecked();

        await page.route('**/UpdateRosterWarningPreference**', async (route) => route.abort());
        await warningButton.click();
        await expect(warningButton).toHaveText('Show roster warnings');
        await expect(warningSwitch).not.toBeChecked();
        await expect(warningSwitch).toHaveAttribute('aria-checked', 'false');
        await page.unroute('**/UpdateRosterWarningPreference**');

        await page.reload();
        await expect(page.locator('.roster-grid-frame')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await openRosterSettings(page);
        await expect(warningButton).toHaveText('Show roster warnings');
        await expect(warningSwitch).toBeChecked();
        await expect(warningSwitch).toHaveAttribute('aria-checked', 'true');
    });
});
