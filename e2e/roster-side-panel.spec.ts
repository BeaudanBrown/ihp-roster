import { expect, test } from '@playwright/test';
import {
    rosterSidePanelDomAttr,
    rosterSidePanelLabelDomAttr,
    rosterSidePanelRootDomAttr,
    rosterSidePanelStates,
    rosterSidePanelToggleDomAttr,
} from '../frontend/ts/generated/contracts';
import { openRoster } from './test-helpers';
import { E2E_TIMEOUT } from './timeouts';

test.describe('Roster side-panel toggle', () => {
    test('expands roster and hides the staff panel until toggled off', async ({ page }) => {
        await page.setViewportSize({ width: 1440, height: 900 });
        await openRoster(page, { rosterLayoutMode: 'day_columns' });

        const shell = page.locator(`[${rosterSidePanelRootDomAttr}="true"]`);
        const main = page.locator('#roster-content');
        const staffPanel = page.locator('#roster-staff-panel-fragment');
        const expandButton = shell.locator(`[${rosterSidePanelToggleDomAttr}="true"]`);

        await expect(staffPanel).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(expandButton).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        const initialMainWidth = await main.boundingBox().then((box) => box?.width ?? 0);

        await expandButton.click();

        await expect(shell).toHaveAttribute(rosterSidePanelDomAttr, rosterSidePanelStates.expanded, { timeout: E2E_TIMEOUT.assertion });
        await expect(staffPanel).toBeHidden({ timeout: E2E_TIMEOUT.assertion });
        await expect(expandButton).toHaveAttribute('aria-label', 'Show side panel');
        await expect(expandButton).toHaveAttribute('aria-pressed', 'true');
        await expect(expandButton.locator(`[${rosterSidePanelLabelDomAttr}="true"]`)).toHaveText('Show side panel');
        await expect.poll(async () => {
            const box = await main.boundingBox();
            return box?.width ?? 0;
        }, { timeout: E2E_TIMEOUT.assertion }).toBeGreaterThan(initialMainWidth);

        await expandButton.click();

        await expect(shell).toHaveAttribute(rosterSidePanelDomAttr, rosterSidePanelStates.collapsed, { timeout: E2E_TIMEOUT.assertion });
        await expect(staffPanel).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(expandButton).toHaveAttribute('aria-label', 'Expand main content');
        await expect(expandButton).toHaveAttribute('aria-pressed', 'false');

        await expandButton.click();
        await expect(shell).toHaveAttribute(rosterSidePanelDomAttr, rosterSidePanelStates.expanded);
        await page.keyboard.press('Escape');
        await expect(shell).toHaveAttribute(rosterSidePanelDomAttr, rosterSidePanelStates.collapsed);
        await expect(staffPanel).toBeVisible();
    });
});
