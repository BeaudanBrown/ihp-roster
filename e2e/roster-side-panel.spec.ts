import { expect, test } from '@playwright/test';
import {
    rosterSidePanelDomAttr,
    rosterSidePanelLabelDomAttr,
    rosterSidePanelRootDomAttr,
    rosterSidePanelStates,
    rosterSidePanelToggleDomAttr,
    rosterSelfServicePanelTabDomAttr,
} from '../frontend/ts/generated/contracts';
import { gotoWhenReady } from './support/runtime';
import { loginAs } from './support/session';
import { openRoster } from './support/roster';
import { E2E_TIMEOUT } from './timeouts';

test.describe('Roster side-panel toggle', () => {
    test('expands roster and hides the staff panel until toggled off', async ({ page }) => {
        await page.setViewportSize({ width: 1440, height: 900 });
        await openRoster(page, { rosterLayoutMode: 'day_columns' });

        const shell = page.locator(`[${rosterSidePanelRootDomAttr}="true"]`);
        const main = page.locator('#roster-content');
        const staffPanel = page.locator('#roster-staff-panel-fragment');
        const expandButton = shell.locator(`[${rosterSidePanelToggleDomAttr}="true"]`);

        await expect(page.getByRole('tab', { name: 'Templates', exact: true })).toBeVisible();
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

    test('gives ordinary staff Quick tools and Settings with mobile SidePanel behavior', async ({ page }) => {
        await page.setViewportSize({ width: 390, height: 844 });
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await gotoWhenReady(page, '/RosterWeeks', '#roster-week-shell');

        const quickToolsTab = page.locator(`[${rosterSelfServicePanelTabDomAttr}="quick-tools"]`);
        const settingsTab = page.locator(`[${rosterSelfServicePanelTabDomAttr}="settings"]`);
        await expect(quickToolsTab).toHaveAttribute('aria-selected', 'true');
        await expect(page.locator('#roster-self-service-quick-tools-pane')).toBeVisible();

        await settingsTab.click();
        await expect(settingsTab).toHaveAttribute('aria-selected', 'true');
        await expect(page.locator('#roster-self-service-settings-pane')).toBeVisible();
        await expect(page.locator('#highlight-own-live-shifts')).toBeVisible();

        await expect(page.locator(`[${rosterSidePanelToggleDomAttr}="true"]`)).toBeHidden();
        await expect(page.locator(`[${rosterSidePanelRootDomAttr}="true"]`)).toHaveAttribute(rosterSidePanelDomAttr, rosterSidePanelStates.collapsed);
        await expect(page.locator('#roster-staff-self-service-panel-fragment')).toBeVisible();
    });
});
