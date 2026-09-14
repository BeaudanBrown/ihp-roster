import { expect, test } from '@playwright/test';
import {
    dialogOverlayMountDomId,
    leaveRequestsLeaveSidePanelDomAttr,
    leaveRequestsLeaveSidePanelPanelDomAttr,
    leaveRequestsLeaveSidePanelStates,
    leaveRequestsLeaveSidePanelTabDomAttr,
    leaveRequestsLeaveSidePanelToggleDomAttr,
    leaveRequestsLeaveStaffHighlightMemberDomAttr,
    leaveRequestsLeaveStaffHighlightPinDomAttr,
    leaveRequestsLeaveStaffHighlightSourceDomAttr,
    leaveRequestsLeaveStaffPanelSortControlDomAttr,
    leaveRequestsLeaveStaffPanelSortRowDomAttr,
} from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady } from './support/runtime';
import { loginAs } from './support/session';

async function openManagerUnavailability(page: Parameters<typeof loginAs>[0]) {
    await loginAs(page, 'e2e-test@example.com', 'test-password-123');
    await gotoWhenReady(page, '/LeaveRequests', '#leave-requests-shell');
}

test.describe('Unavailability shared SidePanel', () => {
    test.describe.configure({ timeout: E2E_TIMEOUT.slowTest });

    test('supports complete inventory, sorting, linked highlights, pinning, and profile launch', async ({ page }) => {
        await page.setViewportSize({ width: 1440, height: 900 });
        await openManagerUnavailability(page);

        const panel = page.locator(`[${leaveRequestsLeaveSidePanelPanelDomAttr}]`);
        await expect(panel).toBeVisible();
        await expect(page.locator(`[${leaveRequestsLeaveSidePanelToggleDomAttr}]`)).toBeVisible();
        await expect(panel.locator(`[${leaveRequestsLeaveSidePanelTabDomAttr}="staff"]`)).toHaveAttribute('aria-selected', 'true');

        const rows = panel.locator(`[${leaveRequestsLeaveStaffHighlightSourceDomAttr}]`);
        expect(await rows.count()).toBeGreaterThan(1);

        const countSort = panel.locator(`[${leaveRequestsLeaveStaffPanelSortControlDomAttr}="count"]`);
        await countSort.click();
        await countSort.click();
        const sortedCounts = await panel.locator(`[${leaveRequestsLeaveStaffPanelSortRowDomAttr}]`).evaluateAll((elements, rowAttr) =>
            elements.map((element) => JSON.parse(element.getAttribute(rowAttr as string) ?? '{}').periodCount as number),
        leaveRequestsLeaveStaffPanelSortRowDomAttr);
        expect(sortedCounts).toEqual([...sortedCounts].sort((left, right) => right - left));

        const firstPeriod = page.locator(`[${leaveRequestsLeaveStaffHighlightMemberDomAttr}]`).first();
        const staffKey = await firstPeriod.getAttribute(leaveRequestsLeaveStaffHighlightMemberDomAttr);
        expect(staffKey).toBeTruthy();
        const matchingSource = panel.locator(`[${leaveRequestsLeaveStaffHighlightSourceDomAttr}="${staffKey}"]`);
        const matchingPeriods = page.locator(`[${leaveRequestsLeaveStaffHighlightMemberDomAttr}="${staffKey}"]`);
        await matchingSource.hover();
        await expect(matchingPeriods.first()).toHaveClass(/is-linked-highlight-member/);

        const pin = matchingSource.locator(`[${leaveRequestsLeaveStaffHighlightPinDomAttr}]`);
        await pin.click();
        await expect(pin).toHaveAttribute('aria-pressed', 'true');
        await page.locator('#leave-request-manager-sections').hover();
        await expect(matchingPeriods.first()).toHaveClass(/is-linked-highlight-member/);
        await expect(page.locator(`#${dialogOverlayMountDomId}`).getByRole('dialog')).toHaveCount(0);

        await pin.click();
        await expect(pin).toHaveAttribute('aria-pressed', 'false');

        const toggle = page.locator(`[${leaveRequestsLeaveSidePanelToggleDomAttr}]`);
        await toggle.click();
        await expect(page.locator(`[${leaveRequestsLeaveSidePanelDomAttr}]`)).toHaveAttribute(
            leaveRequestsLeaveSidePanelDomAttr,
            leaveRequestsLeaveSidePanelStates.expanded,
        );
        await expect(panel).toBeHidden();
        await toggle.click();
        await expect(panel).toBeVisible();

        await matchingSource.click();
        await expect(page.locator(`#${dialogOverlayMountDomId}`).getByRole('dialog')).toBeVisible();
    });

    test('keeps the manager panel responsive on mobile', async ({ page }) => {
        await page.setViewportSize({ width: 390, height: 844 });
        await openManagerUnavailability(page);

        const panel = page.locator(`[${leaveRequestsLeaveSidePanelPanelDomAttr}]`);
        await expect(panel).toBeVisible();
        await expect(page.locator(`[${leaveRequestsLeaveSidePanelTabDomAttr}="staff"]`)).toHaveAttribute('aria-selected', 'true');
        await page.getByRole('tab', { name: 'Settings' }).click();
        await expect(page.locator('#unavailability-blackouts')).toBeVisible();
        expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
        await expect(page.locator(`[${leaveRequestsLeaveSidePanelToggleDomAttr}]`)).toBeHidden();
    });
});
