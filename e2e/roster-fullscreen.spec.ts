import { expect, test } from '@playwright/test';
import {
    rosterFullscreenDomAttr,
    rosterFullscreenLabelDomAttr,
    rosterFullscreenRootDomAttr,
    rosterFullscreenStates,
    rosterFullscreenToggleDomAttr,
} from '../frontend/ts/generated/contracts';
import { openRoster } from './test-helpers';
import { E2E_TIMEOUT } from './timeouts';

test.describe('Roster fullscreen toggle', () => {
    test('expands roster and hides the staff panel until toggled off', async ({ page }) => {
        await page.setViewportSize({ width: 1440, height: 900 });
        await openRoster(page, { rosterLayoutMode: 'day_columns' });

        const shell = page.locator(`[${rosterFullscreenRootDomAttr}="true"]`);
        const main = page.locator('#roster-content');
        const staffPanel = page.locator('#roster-staff-panel-fragment');
        const expandButton = shell.locator(`[${rosterFullscreenToggleDomAttr}="true"]`);

        await expect(staffPanel).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(expandButton).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        const initialMainWidth = await main.boundingBox().then((box) => box?.width ?? 0);

        await expandButton.click();

        await expect(shell).toHaveAttribute(rosterFullscreenDomAttr, rosterFullscreenStates.expanded, { timeout: E2E_TIMEOUT.assertion });
        await expect(staffPanel).toBeHidden({ timeout: E2E_TIMEOUT.assertion });
        await expect(expandButton).toHaveAttribute('aria-label', 'Exit expanded roster');
        await expect(expandButton).toHaveAttribute('aria-pressed', 'true');
        await expect(expandButton.locator(`[${rosterFullscreenLabelDomAttr}="true"]`)).toHaveText('Exit expanded roster');
        await expect.poll(async () => {
            const box = await main.boundingBox();
            return box?.width ?? 0;
        }, { timeout: E2E_TIMEOUT.assertion }).toBeGreaterThan(initialMainWidth);

        await expandButton.click();

        await expect(shell).toHaveAttribute(rosterFullscreenDomAttr, rosterFullscreenStates.collapsed, { timeout: E2E_TIMEOUT.assertion });
        await expect(staffPanel).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(expandButton).toHaveAttribute('aria-label', 'Expand roster');
        await expect(expandButton).toHaveAttribute('aria-pressed', 'false');

        await expandButton.click();
        await expect(shell).toHaveAttribute(rosterFullscreenDomAttr, rosterFullscreenStates.expanded);
        await page.keyboard.press('Escape');
        await expect(shell).toHaveAttribute(rosterFullscreenDomAttr, rosterFullscreenStates.collapsed);
        await expect(staffPanel).toBeVisible();
    });
});
