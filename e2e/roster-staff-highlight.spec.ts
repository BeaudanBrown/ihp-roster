import { test, expect, Page } from '@playwright/test';
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

async function firstAssignedStaffId(page: Page) {
    const assignedLauncher = page
        .locator('[data-roster-shift-launcher="true"][data-roster-staff-id]:not([data-roster-staff-id=""])')
        .first();
    await expect(assignedLauncher).toBeVisible();
    return (await assignedLauncher.getAttribute('data-roster-staff-id')) ?? '';
}

async function chooseRosterLayout(page: Page, layoutMode: 'day_rows' | 'day_columns') {
    await ensureRosterLayout(page, layoutMode);
}

async function hoverStaffRow(page: Page, staffId: string) {
    const staffRow = page.locator(`.roster-staff-panel-entry[data-roster-staff-id="${staffId}"]`).first();
    await expect(staffRow).toBeVisible();
    await staffRow.hover();
    await expect(staffRow).toHaveClass(/is-roster-staff-highlighted/);
}

async function toggleLocateShifts(page: Page, staffId: string) {
    const staffRow = page.locator(`.roster-staff-panel-entry[data-roster-staff-id="${staffId}"]`).first();
    await expect(staffRow).toBeVisible();

    const locateButton = staffRow.locator('[data-roster-staff-highlight-toggle="true"]');
    await staffRow.hover();
    await expect(locateButton).toBeVisible();
    await locateButton.click();
    await expect(locateButton).toHaveAttribute('aria-pressed', 'true');
}

async function gridSlotMetrics(page: Page, staffId: string): Promise<GridSlotMetrics> {
    return await page.evaluate((targetStaffId) => {
        const staffCells = Array.from(
            document.querySelectorAll<HTMLElement>(
                '.roster-grid [role="gridcell"][data-roster-staff-id][data-roster-slot-id]',
            ),
        ).filter((cell) => cell.dataset.rosterStaffId === targetStaffId && cell.dataset.rosterSlotId);
        const slotId = staffCells[0]?.dataset.rosterSlotId ?? '';
        const slotCells = staffCells.filter((cell) => cell.dataset.rosterSlotId === slotId);
        const lastCell = slotCells[slotCells.length - 1] ?? null;
        const lastControl = lastCell?.querySelector<HTMLElement>('.slot-cell-static') ?? null;
        const lastControlRect = lastControl?.getBoundingClientRect();

        return {
            slotCellCount: slotCells.length,
            highlightedCount: slotCells.filter((cell) => cell.classList.contains('is-roster-staff-slot-highlighted')).length,
            startCount: slotCells.filter((cell) => cell.classList.contains('is-roster-staff-slot-highlighted-start')).length,
            endCount: slotCells.filter((cell) => cell.classList.contains('is-roster-staff-slot-highlighted-end')).length,
            lastBorderRightWidth: lastCell ? getComputedStyle(lastCell).borderRightWidth : '',
            lastBoxShadow: lastCell ? getComputedStyle(lastCell).boxShadow : '',
            lastControlLeft: lastControlRect?.left ?? null,
            lastControlWidth: lastControlRect?.width ?? null,
        };
    }, staffId);
}

test.describe('Roster staff shift highlight', () => {
    test.use({ viewport: { width: 1440, height: 900 } });

    test('highlights the assigned slot outline in the row grid without changing cell borders', async ({ page }) => {
        await openRoster(page, { email: 'e2e-test@example.com' });
        await chooseRosterLayout(page, 'day_rows');

        const staffId = await firstAssignedStaffId(page);
        expect(staffId).not.toBe('');

        const beforeHover = await gridSlotMetrics(page, staffId);
        expect(beforeHover.slotCellCount).toBeGreaterThan(0);

        await hoverStaffRow(page, staffId);

        const afterHover = await gridSlotMetrics(page, staffId);
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

        const staffId = await firstAssignedStaffId(page);
        expect(staffId).not.toBe('');

        await chooseRosterLayout(page, 'day_columns');

        await hoverStaffRow(page, staffId);

        const highlightedCards = page.locator(`.roster-shift-card[data-roster-staff-id="${staffId}"].is-roster-staff-slot-highlighted`);
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

        const staffId = await firstAssignedStaffId(page);
        expect(staffId).not.toBe('');

        await toggleLocateShifts(page, staffId);

        const highlightedCells = page.locator(`.roster-grid [role="gridcell"][data-roster-staff-id="${staffId}"].is-roster-staff-slot-highlighted`);
        await expect(highlightedCells.first()).toBeVisible();

        await page.locator('.roster-grid').hover();
        await expect(highlightedCells.first()).toBeVisible();

        const staffRow = page.locator(`.roster-staff-panel-entry[data-roster-staff-id="${staffId}"]`).first();
        await staffRow.getByRole('button', { name: /Locate shifts for/ }).click();
        await expect(highlightedCells).toHaveCount(0);
    });
});
