import { expect, test } from '@playwright/test';
import { openRoster } from './test-helpers';
import { E2E_TIMEOUT } from './timeouts';

test.describe('Roster fullscreen toggle', () => {
    test('expands roster and hides the staff panel until toggled off', async ({ page }) => {
        await page.setViewportSize({ width: 1440, height: 900 });
        await openRoster(page, { rosterLayoutMode: 'day_columns' });

        const shell = page.locator('#roster-week-shell');
        const main = page.locator('#roster-content');
        const staffPanel = page.locator('#roster-staff-panel-fragment');
        const expandButton = page.getByRole('button', { name: 'Expand roster' });

        await expect(staffPanel).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(expandButton).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        const initialMainWidth = await main.boundingBox().then((box) => box?.width ?? 0);

        await expandButton.click();

        await expect(shell).toHaveAttribute('data-roster-fullscreen', 'true', { timeout: E2E_TIMEOUT.assertion });
        await expect(staffPanel).toBeHidden({ timeout: E2E_TIMEOUT.assertion });
        await expect(page.getByRole('button', { name: 'Exit expanded roster' })).toHaveAttribute('aria-pressed', 'true');
        await expect.poll(async () => {
            const box = await main.boundingBox();
            return box?.width ?? 0;
        }, { timeout: E2E_TIMEOUT.assertion }).toBeGreaterThan(initialMainWidth);

        await page.getByRole('button', { name: 'Exit expanded roster' }).click();

        await expect(shell).toHaveAttribute('data-roster-fullscreen', 'false', { timeout: E2E_TIMEOUT.assertion });
        await expect(staffPanel).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(page.getByRole('button', { name: 'Expand roster' })).toHaveAttribute('aria-pressed', 'false');
    });
});
