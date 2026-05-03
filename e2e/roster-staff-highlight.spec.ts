import { test, expect, Page } from '@playwright/test';
import { openRoster } from './test-helpers';

type GridSlotMetrics = {
    slotCellCount: number;
    highlightedCount: number;
    startCount: number;
    endCount: number;
    lastBorderRightWidth: string;
    lastPseudoBorderRightWidth: string;
    lastControlLeft: number | null;
    lastControlWidth: number | null;
};

async function firstStaffOptionValue(page: Page) {
    const staffSelect = page.locator('select[name="staffId"]').first();
    await expect(staffSelect).toBeVisible();

    return await staffSelect.evaluate((select) => {
        if (!(select instanceof HTMLSelectElement)) return '';

        const option = Array.from(select.options).find((candidate) => candidate.value);
        return option?.value ?? '';
    });
}

async function assignFirstSlotToStaff(page: Page, staffId: string) {
    const staffSelect = page.locator('select[name="staffId"]').first();
    await staffSelect.selectOption(staffId);
    await expect(staffSelect).toHaveValue(staffId);

    await expect
        .poll(async () =>
            await page
                .locator(`.roster-grid [role="gridcell"][data-roster-staff-id="${staffId}"][data-roster-slot-id]`)
                .count(),
        )
        .toBeGreaterThan(0);
}

async function chooseRosterLayout(page: Page, layoutMode: 'day_rows' | 'day_columns') {
    await page.getByRole('button', { name: 'Roster actions' }).click();
    await page.locator(`label[for="roster-layout-mode-${layoutMode}"]`).click();

    if (layoutMode === 'day_columns') {
        await expect(page.locator('.roster-day-columns')).toBeVisible();
    } else {
        await expect(page.locator('.roster-grid-frame[data-roster-layout="day_rows"]')).toBeVisible();
    }
}

async function hoverStaffRow(page: Page, staffId: string) {
    const staffRow = page.locator(`.roster-staff-panel-entry[data-roster-staff-id="${staffId}"]`).first();
    await expect(staffRow).toBeVisible();
    await staffRow.hover();
    await expect(staffRow).toHaveClass(/is-roster-staff-highlighted/);
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
        const lastControl = lastCell?.querySelector<HTMLElement>(
            '.slot-cell-input, .slot-time-trigger, .slot-cell-static',
        ) ?? null;
        const lastControlRect = lastControl?.getBoundingClientRect();

        return {
            slotCellCount: slotCells.length,
            highlightedCount: slotCells.filter((cell) => cell.classList.contains('is-roster-staff-slot-highlighted')).length,
            startCount: slotCells.filter((cell) => cell.classList.contains('is-roster-staff-slot-highlighted-start')).length,
            endCount: slotCells.filter((cell) => cell.classList.contains('is-roster-staff-slot-highlighted-end')).length,
            lastBorderRightWidth: lastCell ? getComputedStyle(lastCell).borderRightWidth : '',
            lastPseudoBorderRightWidth: lastCell ? getComputedStyle(lastCell, '::after').borderRightWidth : '',
            lastControlLeft: lastControlRect?.left ?? null,
            lastControlWidth: lastControlRect?.width ?? null,
        };
    }, staffId);
}

test.describe('Roster staff shift highlight', () => {
    test('highlights the assigned slot outline in the row grid without changing cell borders', async ({ page }) => {
        await openRoster(page, { email: 'e2e-test@example.com' });
        await chooseRosterLayout(page, 'day_rows');

        const staffId = await firstStaffOptionValue(page);
        expect(staffId).not.toBe('');
        await assignFirstSlotToStaff(page, staffId);

        const beforeHover = await gridSlotMetrics(page, staffId);
        expect(beforeHover.slotCellCount).toBeGreaterThan(0);

        await hoverStaffRow(page, staffId);

        const afterHover = await gridSlotMetrics(page, staffId);
        expect(afterHover.highlightedCount).toBe(afterHover.slotCellCount);
        expect(afterHover.startCount).toBe(1);
        expect(afterHover.endCount).toBe(1);
        expect(afterHover.lastPseudoBorderRightWidth).toBe('3px');
        expect(afterHover.lastBorderRightWidth).toBe(beforeHover.lastBorderRightWidth);
        expect(afterHover.lastControlLeft ?? 0).toBeCloseTo(beforeHover.lastControlLeft ?? 0, 0);
        expect(afterHover.lastControlWidth ?? 0).toBeCloseTo(beforeHover.lastControlWidth ?? 0, 0);
    });

    test('highlights assigned shift cards in the day-column view', async ({ page }) => {
        await openRoster(page, { email: 'e2e-test@example.com' });
        await chooseRosterLayout(page, 'day_rows');

        const staffId = await firstStaffOptionValue(page);
        expect(staffId).not.toBe('');
        await assignFirstSlotToStaff(page, staffId);

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
});
