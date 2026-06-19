import { test, expect } from '@playwright/test';
import { openRoster } from './test-helpers';

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

async function measureRosterLayout(page: Parameters<typeof openRoster>[0]): Promise<RosterLayoutMetrics> {
    return page.locator('.roster-grid-frame').first().evaluate((frame) => {
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
    });
}

test.describe('Roster layout scale baseline', () => {
    for (const width of [1280, 1366, 1440]) {
        test(`keeps normal roster layout contained at ${width}px`, async ({ page }) => {
            await page.setViewportSize({ width, height: 900 });
            await openRoster(page, { ensureEditable: false });

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
        });
    }
});
