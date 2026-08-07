import { expect, test, type Locator } from '@playwright/test';
import {
    FrontendSurfaceCompleteSetSortRegistry,
    FrontendSurfaceSidePanelRegistry,
    FrontendSurfaceTabSetRegistry,
    type FrontendSurfaceName,
} from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT, gotoWhenReady, loginAs } from './test-helpers';

type SidePanelPage = {
    surface: Extract<FrontendSurfaceName, 'roster' | 'timesheets' | 'leave-requests'>;
    path: string;
    shell: string;
};

const managerPages: SidePanelPage[] = [
    { surface: 'roster', path: '/RosterWeeks', shell: '#roster-week-shell' },
    { surface: 'timesheets', path: '/Timesheets', shell: '#timesheet-week-shell' },
    { surface: 'leave-requests', path: '/LeaveRequests', shell: '#leave-requests-content' },
];

async function openPage(page: Parameters<typeof gotoWhenReady>[0], target: SidePanelPage) {
    await gotoWhenReady(page, target.path, target.shell);
    const sidePanel = FrontendSurfaceSidePanelRegistry[target.surface][0];
    if (!sidePanel) throw new Error(`Missing SidePanel contract for ${target.surface}`);
    const root = page.locator(`[${sidePanel.rootRoleAttribute}="true"]`);
    await expect(root).toHaveCount(1);
    return { root, sidePanel };
}

async function staffNamesByKey(root: Locator, target: SidePanelPage) {
    const sortDefinition = FrontendSurfaceCompleteSetSortRegistry[target.surface][0];
    if (!sortDefinition) throw new Error(`Missing staff sort contract for ${target.surface}`);
    const rows = await root.locator(`[${sortDefinition.rowRoleAttribute}]`).evaluateAll((elements, rowAttribute) =>
        elements.map(element => JSON.parse(element.getAttribute(rowAttribute) ?? '{}') as { staffRowKey: string; staffName: string }),
        sortDefinition.rowRoleAttribute,
    );
    return new Map(rows.map(row => [row.staffRowKey, row.staffName]));
}

async function managerPanelVisualContract(root: Locator) {
    const panel = root.locator('.app-side-panel-region');
    const staffTab = panel.getByRole('tab', { name: 'Staff' });
    const firstHeader = panel.locator('table thead th').first();
    const firstRole = panel.locator('table tbody tr').first().locator('td').first();
    const firstLocate = panel.getByRole('button', { name: /^Locate/ }).first();

    await expect(staffTab).toBeVisible();
    await expect(firstHeader).toBeVisible();
    await expect(firstRole).toBeVisible();
    await expect(firstLocate).toBeVisible();

    return {
        tabs: await staffTab.locator('..').evaluate(element => {
            const style = getComputedStyle(element);
            return [style.display, style.gridTemplateColumns.split(' ').length.toString(), style.gap, style.padding, style.borderRadius, style.backgroundColor];
        }),
        tab: await staffTab.evaluate(element => {
            const style = getComputedStyle(element);
            return [style.minHeight, style.borderRadius, style.fontSize, style.fontWeight, style.backgroundColor, style.color];
        }),
        header: await firstHeader.evaluate(element => {
            const style = getComputedStyle(element);
            return [style.paddingTop, style.paddingBottom, style.fontSize, style.fontWeight, style.letterSpacing, style.textTransform];
        }),
        role: await firstRole.evaluate(element => {
            const style = getComputedStyle(element);
            return [style.fontSize, style.fontWeight, style.letterSpacing, style.textTransform, style.color];
        }),
        locate: await firstLocate.evaluate(element => {
            const style = getComputedStyle(element);
            return [style.width, style.height, style.borderRadius, style.paddingTop, style.paddingRight];
        }),
    };
}

test.describe('cross-page SidePanel consistency', () => {
    test.describe.configure({ timeout: E2E_TIMEOUT.slowTest });

    test('keeps one desktop header location, default tab, transient visibility, focus, and Escape contract', async ({ page }) => {
        await page.setViewportSize({ width: 1440, height: 900 });
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');

        for (const target of managerPages) {
            const { root, sidePanel } = await openPage(page, target);
            const main = root.locator(`[${sidePanel.mainRoleAttribute}="true"]`);
            const panel = root.locator(`[${sidePanel.panelRoleAttribute}="true"]`);
            const header = main.locator('.app-side-panel-header').first();
            const toggle = header.locator(`[${sidePanel.toggleRoleAttribute}="true"]`);
            const tabSet = FrontendSurfaceTabSetRegistry[target.surface][0];
            if (!tabSet) throw new Error(`Missing TabSet contract for ${target.surface}`);

            await expect(header).toBeVisible();
            await expect(toggle).toBeVisible();
            await expect(panel).toBeVisible();
            await expect(root).toHaveAttribute(sidePanel.stateAttribute, sidePanel.collapsedValue);
            await expect(root.locator(`[${tabSet.tabRoleAttribute}="${tabSet.defaultKey}"]`)).toHaveAttribute('aria-selected', 'true');

            const [headerBox, toggleBox] = await Promise.all([header.boundingBox(), toggle.boundingBox()]);
            expect(headerBox).not.toBeNull();
            expect(toggleBox).not.toBeNull();
            expect((toggleBox?.x ?? 0) + (toggleBox?.width ?? 0)).toBeLessThanOrEqual((headerBox?.x ?? 0) + (headerBox?.width ?? 0) + 1);

            await toggle.click();
            await expect(toggle).toBeFocused();
            await expect(root).toHaveAttribute(sidePanel.stateAttribute, sidePanel.expandedValue);
            await expect(panel).toBeHidden();
            await page.keyboard.press('Escape');
            await expect(root).toHaveAttribute(sidePanel.stateAttribute, sidePanel.collapsedValue);
            await expect(panel).toBeVisible();
        }

        const roster = managerPages[0]!;
        const { root, sidePanel } = await openPage(page, roster);
        await root.locator(`[${sidePanel.toggleRoleAttribute}="true"]`).click();
        await expect(root).toHaveAttribute(sidePanel.stateAttribute, sidePanel.expandedValue);
        await page.reload();
        await expect(page.locator(`[${sidePanel.rootRoleAttribute}="true"]`)).toHaveAttribute(sidePanel.stateAttribute, sidePanel.collapsedValue);
    });

    test('uses Roster staff names for matching staff on every manager panel', async ({ page }) => {
        await page.setViewportSize({ width: 1440, height: 900 });
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');

        const roster = managerPages[0]!;
        const { root: rosterRoot } = await openPage(page, roster);
        const rosterNames = await staffNamesByKey(rosterRoot, roster);

        for (const target of managerPages.slice(1)) {
            const { root } = await openPage(page, target);
            const targetNames = await staffNamesByKey(root, target);
            const sharedStaff = [...targetNames].filter(([staffKey]) => rosterNames.has(staffKey));
            expect(sharedStaff.length).toBeGreaterThan(0);
            for (const [staffKey, staffName] of sharedStaff) {
                expect(staffName, `${target.surface} name for ${staffKey}`).toBe(rosterNames.get(staffKey));
            }
        }
    });

    test('uses the Roster visual contract for every manager panel', async ({ page }) => {
        await page.setViewportSize({ width: 1440, height: 900 });
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');

        const roster = managerPages[0]!;
        const { root: rosterRoot } = await openPage(page, roster);
        const expectedVisualContract = await managerPanelVisualContract(rosterRoot);

        for (const target of managerPages.slice(1)) {
            const { root } = await openPage(page, target);
            expect(await managerPanelVisualContract(root)).toEqual(expectedVisualContract);
        }
    });

    test('stacks every panel without page-level horizontal overflow on phone widths', async ({ page }) => {
        await page.setViewportSize({ width: 390, height: 844 });
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');

        for (const target of managerPages) {
            const { root, sidePanel } = await openPage(page, target);
            await expect(root.locator(`[${sidePanel.toggleRoleAttribute}="true"]`)).toBeHidden();
            await expect(root.locator(`[${sidePanel.panelRoleAttribute}="true"]`)).toBeVisible();
            expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
        }
    });
});
