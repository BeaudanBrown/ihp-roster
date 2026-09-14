import { test, expect, Page } from '@playwright/test';
import { dialogMountDomAttr, dialogOverlayMountDomId } from '../frontend/ts/generated/contracts';
import { openRoster } from './support/roster';

type RosterLayoutMetrics = {
    viewportWidth: number;
    rootScrollWidth: number;
    bodyScrollWidth: number;
    frameWidth: number;
    dayRailWidth: number;
    wageRailWidth: number | null;
    scrollerClientWidth: number;
    scrollerScrollWidth: number;
    gridFontSize: number;
    cellFontSize: number;
    gridMinWidth: string;
    overflowX: string;
};

async function setRosterScale(page: Page, scale: 'compact' | 'normal' | 'large') {
    await page.evaluate((nextScale) => {
        document.documentElement.setAttribute('data-ui-scale', nextScale);
    }, scale);
}

async function measureRosterLayout(page: Page, options: { slotCount?: number } = {}): Promise<RosterLayoutMetrics> {
    return page.locator('.roster-grid-frame').first().evaluate((frame, measureOptions) => {
        if (!(frame instanceof HTMLElement)) {
            throw new Error('Expected roster grid frame to be an HTMLElement');
        }

        const dayRail = frame.querySelector('.roster-day-rail');
        const wageRail = frame.querySelector('.roster-wage-rail');
        const scroller = frame.querySelector('.roster-slots-scroller');
        const grid = frame.querySelector('.roster-grid');
        const cell = frame.querySelector('.slot-cell-static');

        if (!(dayRail instanceof HTMLElement)
            || !(scroller instanceof HTMLElement)
            || !(grid instanceof HTMLElement)) {
            throw new Error('Roster layout metric selectors were not present');
        }

        if (measureOptions.slotCount !== undefined) {
            scroller.style.setProperty('--roster-slot-count', String(measureOptions.slotCount));
        }

        const gridStyles = getComputedStyle(grid);
        const cellStyles = cell instanceof HTMLElement ? getComputedStyle(cell) : gridStyles;

        return {
            viewportWidth: document.documentElement.clientWidth,
            rootScrollWidth: document.documentElement.scrollWidth,
            bodyScrollWidth: document.body.scrollWidth,
            frameWidth: frame.getBoundingClientRect().width,
            dayRailWidth: dayRail.getBoundingClientRect().width,
            wageRailWidth: wageRail instanceof HTMLElement ? wageRail.getBoundingClientRect().width : null,
            scrollerClientWidth: scroller.clientWidth,
            scrollerScrollWidth: scroller.scrollWidth,
            gridFontSize: Number.parseFloat(gridStyles.fontSize),
            cellFontSize: Number.parseFloat(cellStyles.fontSize),
            gridMinWidth: gridStyles.minWidth,
            overflowX: getComputedStyle(scroller).overflowX,
        };
    }, options);
}

test.describe('Roster layout scale baseline', () => {
    test('keeps normal roster layout contained across desktop widths', async ({ page }) => {
        await page.setViewportSize({ width: 1280, height: 900 });
        await openRoster(page, { ensureEditable: false });

        for (const width of [1280, 1366, 1440]) {
            await page.setViewportSize({ width, height: 900 });
            await expect.poll(() => page.locator('.roster-slots-scroller').evaluate((scroller) =>
                getComputedStyle(scroller).overflowX
            )).toBe('auto');
            const metrics = await measureRosterLayout(page);

            expect(metrics.viewportWidth).toBe(width);
            expect(metrics.rootScrollWidth).toBeLessThanOrEqual(width + 1);
            expect(metrics.bodyScrollWidth).toBeLessThanOrEqual(width + 1);
            expect(metrics.overflowX).toBe('auto');
            expect(metrics.scrollerClientWidth).toBeGreaterThan(0);
            expect(metrics.scrollerScrollWidth).toBeGreaterThanOrEqual(metrics.scrollerClientWidth);
            expect(metrics.gridMinWidth).not.toBe('0px');
            expect(metrics.dayRailWidth).toBeGreaterThan(60);
            expect(metrics.dayRailWidth).toBeLessThan(metrics.frameWidth * 0.25);
            if (metrics.wageRailWidth !== null) {
                expect(metrics.wageRailWidth).toBeGreaterThan(50);
                expect(metrics.wageRailWidth).toBeLessThan(120);
            }
            expect(metrics.gridFontSize).toBeGreaterThanOrEqual(10);
            expect(metrics.gridFontSize).toBeLessThanOrEqual(14);
            expect(metrics.cellFontSize).toBeGreaterThanOrEqual(9);
            expect(metrics.cellFontSize).toBeLessThanOrEqual(14);
        }
    });

    test('changes roster dimensions through scale presets without page-level overflow', async ({ page }) => {
        await page.setViewportSize({ width: 1366, height: 900 });
        await openRoster(page, { ensureEditable: false });

        await setRosterScale(page, 'normal');
        const normal = await measureRosterLayout(page, { slotCount: 8 });

        await setRosterScale(page, 'compact');
        const compact = await measureRosterLayout(page, { slotCount: 8 });

        await setRosterScale(page, 'large');
        const large = await measureRosterLayout(page, { slotCount: 8 });

        expect(compact.dayRailWidth).toBeLessThan(normal.dayRailWidth);
        expect(normal.dayRailWidth).toBeLessThan(large.dayRailWidth);
        expect(compact.gridFontSize).toBeLessThan(normal.gridFontSize);
        expect(normal.gridFontSize).toBeLessThan(large.gridFontSize);
        expect(compact.scrollerScrollWidth).toBeLessThan(normal.scrollerScrollWidth);
        expect(normal.scrollerScrollWidth).toBeLessThan(large.scrollerScrollWidth);

        for (const metrics of [compact, normal, large]) {
            expect(metrics.rootScrollWidth).toBeLessThanOrEqual(metrics.viewportWidth + 1);
            expect(metrics.bodyScrollWidth).toBeLessThanOrEqual(metrics.viewportWidth + 1);
        }
    });

    test('keeps roster shift dialogs clickable across scale presets', async ({ page }) => {
        await page.setViewportSize({ width: 1366, height: 900 });
        await openRoster(page);

        for (const scale of ['compact', 'normal', 'large'] as const) {
            await setRosterScale(page, scale);
            const launcher = page.locator('[data-roster-shift-launcher="true"][hx-get*="EditRosterSlotDialog"]').first();
            await expect(launcher).toBeVisible();
            await launcher.scrollIntoViewIfNeeded();

            const dialogResponsePromise = page.waitForResponse((response) =>
                response.request().method() === 'GET' && response.url().includes('/EditRosterSlotDialog')
            );
            await launcher.click({ force: true });
            const dialogResponse = await dialogResponsePromise;
            expect(dialogResponse.status(), await dialogResponse.text()).toBe(200);

            const dialog = page.locator(`#${dialogOverlayMountDomId} [${dialogMountDomAttr}]`);
            await expect(dialog).toBeVisible();
            await expect(page.locator('#roster-shift-staff-id')).toBeVisible();
            await expect(page.locator('#roster-shift-type-id')).toBeVisible();
            await expect(page.getByRole('button', { name: 'Save' })).toBeVisible();

            await page.getByRole('button', { name: 'Cancel' }).click();
            await expect(dialog).toHaveCount(0);
        }
    });
});
