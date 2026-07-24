import { test, expect, Page } from '@playwright/test';
import {
    rosterStaffHighlightMemberDomAttr,
    rosterStaffHighlightOrderDomAttr,
    rosterStaffHighlightPinDomAttr,
    rosterStaffHighlightSourceDomAttr,
    rosterStaffPanelSortRowDomAttr,
} from '../frontend/ts/generated/contracts';
import { ensureRosterLayout, openRoster } from './test-helpers';

type GridSlotMetrics = {
    slotCellCount: number;
    highlightedCount: number;
    startCount: number;
    endCount: number;
    lastBorderRightWidth: string;
    lastBoxShadow: string;
    lastControlLeft: number | null;
    lastControlWidth: number | null;
};

async function firstAssignedStaffKey(page: Page) {
    const assignedLauncher = page
        .locator(`[data-roster-shift-launcher="true"][${rosterStaffHighlightMemberDomAttr}]`)
        .first();
    await expect(assignedLauncher).toBeVisible();
    return (await assignedLauncher.getAttribute(rosterStaffHighlightMemberDomAttr)) ?? '';
}

async function chooseRosterLayout(page: Page, layoutMode: 'day_rows' | 'day_columns') {
    await ensureRosterLayout(page, layoutMode);
}

async function hoverStaffRow(page: Page, staffKey: string) {
    const staffRow = page.locator(`[${rosterStaffPanelSortRowDomAttr}][${rosterStaffHighlightSourceDomAttr}="${staffKey}"]`).first();
    await expect(staffRow).toBeVisible();
    await staffRow.hover();
    await expect(staffRow).toHaveClass(/is-linked-highlight-source/);
}

async function toggleLocateShifts(page: Page, staffKey: string) {
    const staffRow = page.locator(`[${rosterStaffPanelSortRowDomAttr}][${rosterStaffHighlightSourceDomAttr}="${staffKey}"]`).first();
    await expect(staffRow).toBeVisible();

    const locateButton = staffRow.locator(`[${rosterStaffHighlightPinDomAttr}="${staffKey}"]`);
    await staffRow.hover();
    await expect(locateButton).toBeVisible();
    await locateButton.evaluate((button) => {
        if (!(button instanceof HTMLElement)) throw new Error('Expected locate button');
        button.click();
    });
    await expect(locateButton).toHaveAttribute('aria-pressed', 'true');
}

async function gridSlotMetrics(page: Page, staffKey: string): Promise<GridSlotMetrics> {
    return await page.evaluate(({ targetStaffKey, memberAttr, orderAttr }) => {
        const staffCells = Array.from(
            document.querySelectorAll<HTMLElement>(`.roster-grid [role="gridcell"][${memberAttr}][${orderAttr}]`),
        ).filter((cell) => cell.getAttribute(memberAttr) === targetStaffKey);
        const orderKey = staffCells[0]?.getAttribute(orderAttr) ?? '';
        const slotCells = staffCells.filter((cell) => cell.getAttribute(orderAttr) === orderKey);
        const lastCell = slotCells[slotCells.length - 1] ?? null;
        const lastControl = lastCell?.querySelector<HTMLElement>('.slot-cell-static') ?? null;
        const lastControlRect = lastControl?.getBoundingClientRect();

        return {
            slotCellCount: slotCells.length,
            highlightedCount: slotCells.filter((cell) => cell.classList.contains('is-linked-highlight-member')).length,
            startCount: slotCells.filter((cell) => cell.classList.contains('is-linked-highlight-member-first')).length,
            endCount: slotCells.filter((cell) => cell.classList.contains('is-linked-highlight-member-last')).length,
            lastBorderRightWidth: lastCell ? getComputedStyle(lastCell).borderRightWidth : '',
            lastBoxShadow: lastCell ? getComputedStyle(lastCell).boxShadow : '',
            lastControlLeft: lastControlRect?.left ?? null,
            lastControlWidth: lastControlRect?.width ?? null,
        };
    }, {
        targetStaffKey: staffKey,
        memberAttr: rosterStaffHighlightMemberDomAttr,
        orderAttr: rosterStaffHighlightOrderDomAttr,
    });
}

test.describe('Roster staff shift highlight', () => {
    test.use({ viewport: { width: 1440, height: 900 } });

    test('highlights the assigned slot outline in the row grid without changing cell borders', async ({ page }) => {
        await openRoster(page, { email: 'e2e-test@example.com' });
        await chooseRosterLayout(page, 'day_rows');

        const staffKey = await firstAssignedStaffKey(page);
        expect(staffKey).not.toBe('');

        const beforeHover = await gridSlotMetrics(page, staffKey);
        expect(beforeHover.slotCellCount).toBeGreaterThan(0);

        await hoverStaffRow(page, staffKey);

        const afterHover = await gridSlotMetrics(page, staffKey);
        expect(afterHover.highlightedCount).toBe(afterHover.slotCellCount);
        expect(afterHover.startCount).toBe(1);
        expect(afterHover.endCount).toBe(1);
        expect(afterHover.lastBoxShadow).not.toBe('none');
        expect(afterHover.lastBorderRightWidth).toBe(beforeHover.lastBorderRightWidth);
        expect(afterHover.lastControlLeft ?? 0).toBeCloseTo(beforeHover.lastControlLeft ?? 0, 0);
        expect(afterHover.lastControlWidth ?? 0).toBeCloseTo(beforeHover.lastControlWidth ?? 0, 0);
    });

    test('highlights assigned shift cards in the day-column view', async ({ page }) => {
        await openRoster(page, { email: 'e2e-test@example.com' });
        await chooseRosterLayout(page, 'day_rows');

        const staffKey = await firstAssignedStaffKey(page);
        expect(staffKey).not.toBe('');

        await chooseRosterLayout(page, 'day_columns');

        await hoverStaffRow(page, staffKey);

        const highlightedCards = page.locator(`.roster-shift-card[${rosterStaffHighlightMemberDomAttr}="${staffKey}"].is-linked-highlight-member`);
        await expect(highlightedCards.first()).toBeVisible();
        await expect
            .poll(async () =>
                await highlightedCards.first().evaluate((card) => getComputedStyle(card).boxShadow),
            )
            .not.toBe('none');
    });

    test('toggles a persistent staff highlight from the locate shifts button', async ({ page }) => {
        await openRoster(page, { email: 'e2e-test@example.com' });
        await chooseRosterLayout(page, 'day_rows');

        const staffKey = await firstAssignedStaffKey(page);
        expect(staffKey).not.toBe('');

        await toggleLocateShifts(page, staffKey);

        const highlightedCells = page.locator(`.roster-grid [role="gridcell"][${rosterStaffHighlightMemberDomAttr}="${staffKey}"].is-linked-highlight-member`);
        await expect(highlightedCells.first()).toBeVisible();

        await page.locator('.roster-grid').hover();
        await expect(highlightedCells.first()).toBeVisible();

        const staffRow = page.locator(`[${rosterStaffPanelSortRowDomAttr}][${rosterStaffHighlightSourceDomAttr}="${staffKey}"]`).first();
        await staffRow.getByRole('button', { name: /Locate shifts for/ }).evaluate((button) => {
            if (!(button instanceof HTMLElement)) throw new Error('Expected locate button');
            button.click();
        });
        await expect(highlightedCells).toHaveCount(0);
    });
});
