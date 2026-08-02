import { readFileSync } from 'node:fs';
import { test, expect } from '@playwright/test';
import {
    parseRosterImageExportConfig,
    rosterImageExportCellDomAttr,
    rosterImageExportConfigDomAttr,
    rosterImageExportProjectionDomAttr,
    rosterImageExportTriggerDomAttr,
    rosterWeekOverviewDayDomAttr,
    rosterWeekOverviewPanelDomAttr,
} from '../frontend/ts/generated/contracts';
import { gotoWhenReady, loginAs, openRoster, openRosterSettings, runSql } from './test-helpers';

const e2eRosterPath = '/ShowRosterWeek?weekOffset=0&rosterGroupId=a1000000-0000-0000-0000-000000000211';

test.describe('Roster week overview', () => {
    test('renders a static week label without the month overview trigger', async ({ page }) => {
        await openRoster(page);

        await expect(page.getByRole('button', { name: 'Open roster week overview' })).toHaveCount(0);
        await expect(page.locator(`[${rosterWeekOverviewPanelDomAttr}]`)).toHaveCount(0);
        await expect(page.locator(`[${rosterWeekOverviewDayDomAttr}]`)).toHaveCount(0);
        await expect(page.locator('.roster-week-nav-label')).toContainText('Week of');
    });

    test('exports the live roster as a jpg from the roster actions menu', async ({ page }) => {
        runSql("UPDATE roster_weeks SET is_live = TRUE WHERE id = 'a1000000-0000-0000-0000-000000000053';");
        await openRoster(page, { weekOffset: 1, ensureDraft: false, ensureEditable: false });

        await openRosterSettings(page);
        const exportButton = page.locator(`[${rosterImageExportTriggerDomAttr}="true"]`);
        await expect(exportButton).toBeVisible();
        await expect(exportButton).toHaveText('Export JPG');
        const rawConfig = await exportButton.getAttribute(rosterImageExportConfigDomAttr);
        expect(rawConfig).not.toBeNull();
        const config = parseRosterImageExportConfig(JSON.parse(rawConfig ?? '{}'));

        const exportGeometryPromise = page.evaluate(({ projectionAttr, cellAttr }) => new Promise<{
            dayCellCount: number;
            wageRailDisplay: string | null;
            dayRight: number | null;
            firstSlotLeft: number | null;
            alignedRowCount: number;
        }>((resolve) => {
            const observer = new MutationObserver(() => {
                const projection = document.querySelector<HTMLElement>(`.roster-export-stage [${projectionAttr}]`);
                if (projection === null) return;
                const dayCells = Array.from(projection.querySelectorAll<HTMLElement>(`.roster-day-rail-section[${cellAttr}]`));
                const slotCells = Array.from(projection.querySelectorAll<HTMLElement>(`.day-row [${cellAttr}]`));
                const wageRail = projection.querySelector<HTMLElement>('.roster-wage-rail');
                const firstDay = dayCells[0]?.getBoundingClientRect() ?? null;
                const firstSlot = slotCells[0]?.getBoundingClientRect() ?? null;
                const dayTops = new Set(dayCells.map((cell) => Math.round(cell.getBoundingClientRect().top)));
                const slotTops = new Set(slotCells.map((cell) => Math.round(cell.getBoundingClientRect().top)));
                observer.disconnect();
                resolve({
                    dayCellCount: dayCells.length,
                    wageRailDisplay: wageRail === null ? null : getComputedStyle(wageRail).display,
                    dayRight: firstDay?.right ?? null,
                    firstSlotLeft: firstSlot?.left ?? null,
                    alignedRowCount: Array.from(dayTops).filter((top) => slotTops.has(top)).length,
                });
            });
            observer.observe(document.body, { childList: true });
        }), {
            projectionAttr: rosterImageExportProjectionDomAttr,
            cellAttr: rosterImageExportCellDomAttr,
        });
        const downloadPromise = page.waitForEvent('download');
        await exportButton.click();
        const [download, exportGeometry] = await Promise.all([downloadPromise, exportGeometryPromise]);

        expect(exportGeometry.dayCellCount).toBe(7);
        expect([null, 'none']).toContain(exportGeometry.wageRailDisplay);
        expect(exportGeometry.dayRight).not.toBeNull();
        expect(exportGeometry.firstSlotLeft).not.toBeNull();
        expect(exportGeometry.firstSlotLeft ?? 0).toBeGreaterThanOrEqual((exportGeometry.dayRight ?? 0) - 1);
        expect(exportGeometry.alignedRowCount).toBeGreaterThan(0);

        expect(download.suggestedFilename()).toBe(config.imageExportFilename);
        await expect(exportButton).toHaveText(config.imageExportDownloadedLabel);
        const downloadPath = await download.path();
        expect(downloadPath).not.toBeNull();
        const bytes = readFileSync(downloadPath ?? '');
        expect(Array.from(bytes.subarray(0, 3))).toEqual([0xff, 0xd8, 0xff]);
        expect(bytes.length).toBeGreaterThan(1000);
    });

    test('does not show roster JPG export on draft weeks', async ({ page }) => {
        await openRoster(page, { weekOffset: 2 });

        await openRosterSettings(page);
        await expect(page.getByRole('button', { name: 'Export JPG' })).toHaveCount(0);
    });

    test('keeps a large desktop roster grid fitted without requiring local horizontal scrolling', async ({ page }) => {
        await page.setViewportSize({ width: 1900, height: 900 });
        await openRoster(page);

        const metrics = await page.locator('.roster-grid-frame').first().evaluate((frame) => {
            if (!(frame instanceof HTMLElement)) {
                throw new Error('Expected roster grid frame to be an HTMLElement');
            }

            const scroller = frame.querySelector('.roster-slots-scroller');
            const grid = frame.querySelector('.roster-grid');
            const dayRail = frame.querySelector('.roster-day-rail');

            if (!(scroller instanceof HTMLElement) || !(grid instanceof HTMLElement) || !(dayRail instanceof HTMLElement)) {
                return null;
            }

            return {
                clientWidth: scroller.clientWidth,
                scrollWidth: scroller.scrollWidth,
                frameScrollWidth: frame.scrollWidth,
                frameClientWidth: frame.clientWidth,
                overflowX: getComputedStyle(scroller).overflowX,
                gridMinWidth: getComputedStyle(grid).minWidth,
                dayRailPosition: getComputedStyle(dayRail).position,
            };
        });

        expect(metrics).not.toBeNull();
        expect(metrics?.overflowX).toBe('auto');
        expect(metrics?.scrollWidth).toBeLessThanOrEqual((metrics?.clientWidth ?? 0) + 1);
        expect(metrics?.frameScrollWidth).toBeLessThanOrEqual((metrics?.frameClientWidth ?? 0) + 1);
        expect(metrics?.gridMinWidth).not.toBe('0px');
        expect(metrics?.dayRailPosition).toBe('static');
    });

    test('makes the roster slots locally scrollable on medium viewports when columns do not fit', async ({ page }) => {
        await page.setViewportSize({ width: 1260, height: 900 });
        await openRoster(page, { ensureEditable: false });

        const metrics = await page.locator('.roster-grid-frame').first().evaluate((frame) => {
            if (!(frame instanceof HTMLElement)) {
                throw new Error('Expected roster grid frame to be an HTMLElement');
            }

            const scroller = frame.querySelector('.roster-slots-scroller');
            const grid = frame.querySelector('.roster-grid');

            if (!(scroller instanceof HTMLElement) || !(grid instanceof HTMLElement)) {
                return null;
            }
            scroller.style.setProperty('--roster-slot-count', '4');

            const maxScrollLeft = Math.max(0, scroller.scrollWidth - scroller.clientWidth);
            scroller.scrollLeft = Math.floor(maxScrollLeft / 2);

            return {
                clientWidth: scroller.clientWidth,
                scrollWidth: scroller.scrollWidth,
                scrollLeft: scroller.scrollLeft,
                overflowX: getComputedStyle(scroller).overflowX,
                gridMinWidth: getComputedStyle(grid).minWidth,
                rootScrollWidth: document.documentElement.scrollWidth,
                bodyScrollWidth: document.body.scrollWidth,
                viewportWidth: document.documentElement.clientWidth,
            };
        });

        expect(metrics).not.toBeNull();
        expect(metrics?.overflowX).toBe('auto');
        expect(metrics?.scrollWidth).toBeGreaterThan(metrics?.clientWidth ?? 0);
        expect(metrics?.scrollLeft).toBeGreaterThan(0);
        expect(metrics?.gridMinWidth).not.toBe('0px');
        expect(metrics?.rootScrollWidth).toBeLessThanOrEqual((metrics?.viewportWidth ?? 0) + 1);
        expect(metrics?.bodyScrollWidth).toBeLessThanOrEqual((metrics?.viewportWidth ?? 0) + 1);
    });

    test('worker cannot see manager-only roster controls or leave metrics', async ({ page }) => {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await gotoWhenReady(page, e2eRosterPath, '#roster-week-shell');

        await expect(page.getByLabel('Live')).toHaveCount(0);
        await expect(page.getByRole('button', { name: 'Copy Previous Week' })).toHaveCount(0);

        await expect(page.getByRole('button', { name: 'Export JPG' })).toHaveCount(0);
        await expect(page.getByText('Hide from dropdowns')).toHaveCount(0);
        await expect(page.getByRole('button', { name: 'Sync Slots' })).toHaveCount(0);

        await expect(page.getByRole('button', { name: 'Open roster week overview' })).toHaveCount(0);
        await expect(page.locator(`[${rosterWeekOverviewPanelDomAttr}]`)).toHaveCount(0);
        await expect(page.locator(`[${rosterWeekOverviewDayDomAttr}]`)).toHaveCount(0);
    });
});
