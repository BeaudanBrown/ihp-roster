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
    toggleRootDomAttr,
} from '../frontend/ts/generated/contracts';
import { gotoWhenReady } from './support/runtime';
import { loginAs } from './support/session';
import { openRoster, openRosterSettings } from './support/roster';
import { runSql } from './support/database';

const e2eRosterPath = '/RosterWeeks?rosterGroupId=a1000000-0000-0000-0000-000000000211';

test.describe('Roster week overview', () => {
    test('renders a static week label without the month overview trigger', async ({ page }) => {
        await openRoster(page);

        await expect(page.getByRole('button', { name: 'Open roster week overview' })).toHaveCount(0);
        await expect(page.locator(`[${rosterWeekOverviewPanelDomAttr}]`)).toHaveCount(0);
        await expect(page.locator(`[${rosterWeekOverviewDayDomAttr}]`)).toHaveCount(0);
        await expect(page.locator('.roster-week-nav-label')).toContainText('Week of');
    });

    test('exports the Published roster as colour and print PNGs from the roster actions menu', async ({ page }) => {
        runSql(`
            UPDATE roster_slots
            SET staff_id = NULL, assignment_state = 'open'
            WHERE id = 'a1000000-0000-0000-0000-000000000074';
            WITH target_day AS (
                INSERT INTO roster_days (id, venue_id, roster_group_id, operational_date, publication_state, is_closed, row_count)
                VALUES (
                    'a1000000-0000-0000-0000-000000000064',
                    'a1000000-0000-0000-0000-000000000001',
                    'a1000000-0000-0000-0000-000000000211',
                    CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 8,
                    'draft', FALSE, 1
                )
                ON CONFLICT (roster_group_id, operational_date) DO UPDATE
                SET publication_state = 'draft', is_closed = EXCLUDED.is_closed, row_count = EXCLUDED.row_count
                RETURNING id
            )
            INSERT INTO roster_lanes (id, roster_day_id, name, sort_order)
            SELECT 'a1000000-0000-0000-0000-000000000084', target_day.id, 'Late', 1
            FROM target_day
            ON CONFLICT (id) DO UPDATE
            SET roster_day_id = EXCLUDED.roster_day_id, name = EXCLUDED.name, sort_order = EXCLUDED.sort_order, deleted_at = NULL;
        `);
        await openRoster(page, { weekOffset: 1 });
        const publishToggleRoot = page.locator(`[${toggleRootDomAttr}]`).filter({ hasText: 'Published' });
        const publishToggle = publishToggleRoot.getByRole('switch');
        const publishResponsePromise = page.waitForResponse((response) => response.url().includes('/ToggleRosterWeekLiveStatus'));
        await publishToggleRoot.click();
        expect((await publishResponsePromise).status()).toBe(200);
        await expect(publishToggle).toBeChecked();
        await page.reload();
        await expect(page.locator('#roster-week-shell')).toBeVisible();

        try {
            await openRosterSettings(page);
            const exportButtons = page.locator(`[${rosterImageExportTriggerDomAttr}="true"]`);
            await expect(exportButtons).toHaveCount(2);
            const colourExportButton = exportButtons.nth(0);
            const printExportButton = exportButtons.nth(1);
            await expect(colourExportButton).toHaveText('Export colour PNG');
            await expect(printExportButton).toHaveText('Export print PNG');
            const colourConfig = parseRosterImageExportConfig(JSON.parse(await colourExportButton.getAttribute(rosterImageExportConfigDomAttr) ?? '{}'));
            const config = parseRosterImageExportConfig(JSON.parse(await printExportButton.getAttribute(rosterImageExportConfigDomAttr) ?? '{}'));
            expect(colourConfig.imageExportStyle).toBe('colour');
            expect(colourConfig.imageExportMaximumWidth).toBe(1240);
            expect(config.imageExportStyle).toBe('print');
            expect(config.imageExportMinimumWidth).toBe(920);
            expect(config.imageExportMaximumWidth).toBe(1240);
        const renderedDayCellCount = await page.locator('.roster-day-rail-section').count();
        expect(renderedDayCellCount).toBeGreaterThan(0);

        const sourceDayCellCount = await page.locator(`.roster-day-rail-section[${rosterImageExportCellDomAttr}]`).count();
        expect(sourceDayCellCount).toBeGreaterThanOrEqual(1);
        const exportGeometryPromise = page.evaluate(({ projectionAttr, cellAttr }) => new Promise<{
            dayCellCount: number;
            wageRailDisplay: string | null;
            dayRight: number | null;
            firstSlotLeft: number | null;
            alignedRowCount: number;
            dayRailHeaderDisplay: string | null;
            slotHeaderDisplay: string | null;
            lightDayBackground: string | null;
            darkDayBackground: string | null;
            cellTextAlign: string | null;
            laneBorderWidth: string | null;
            openShiftBoxShadow: string | null;
            openShiftBackground: string | null;
            openShiftFontWeight: string | null;
        }>((resolve) => {
            const observer = new MutationObserver(() => {
                const projection = document.querySelector<HTMLElement>(`.roster-export-stage [${projectionAttr}]`);
                if (projection === null) return;
                const dayCells = Array.from(projection.querySelectorAll<HTMLElement>(`.roster-day-rail-section[${cellAttr}]`));
                const slotCells = Array.from(projection.querySelectorAll<HTMLElement>(`.day-row [${cellAttr}]`));
                const wageRail = projection.querySelector<HTMLElement>('.roster-wage-rail');
                const firstDay = dayCells[0]?.getBoundingClientRect() ?? null;
                const firstSlot = slotCells[0]?.getBoundingClientRect() ?? null;
                const lightDay = projection.querySelector<HTMLElement>('.day-alt-light');
                const darkDay = projection.querySelector<HTMLElement>('.day-alt-dark');
                const laneCell = projection.querySelector<HTMLElement>('.roster-block-start');
                const openShift = projection.querySelector<HTMLElement>('.is-roster-shift-open');
                const dayTops = new Set(dayCells.map((cell) => Math.round(cell.getBoundingClientRect().top)));
                const slotTops = new Set(slotCells.map((cell) => Math.round(cell.getBoundingClientRect().top)));
                observer.disconnect();
                resolve({
                    dayCellCount: dayCells.length,
                    wageRailDisplay: wageRail === null ? null : getComputedStyle(wageRail).display,
                    dayRight: firstDay?.right ?? null,
                    firstSlotLeft: firstSlot?.left ?? null,
                    alignedRowCount: Array.from(dayTops).filter((top) => slotTops.has(top)).length,
                    dayRailHeaderDisplay: (() => {
                        const header = projection.querySelector<HTMLElement>('.roster-day-rail-head');
                        return header === null ? null : getComputedStyle(header).display;
                    })(),
                    slotHeaderDisplay: (() => {
                        const header = projection.querySelector<HTMLElement>('.roster-grid-head');
                        return header === null ? null : getComputedStyle(header).display;
                    })(),
                    lightDayBackground: lightDay === null ? null : getComputedStyle(lightDay).backgroundColor,
                    darkDayBackground: darkDay === null ? null : getComputedStyle(darkDay).backgroundColor,
                    cellTextAlign: firstSlot === null ? null : getComputedStyle(slotCells[0]).textAlign,
                    laneBorderWidth: laneCell === null ? null : getComputedStyle(laneCell).borderLeftWidth,
                    openShiftBoxShadow: openShift === null ? null : getComputedStyle(openShift).boxShadow,
                    openShiftBackground: (() => {
                        const cell = projection.querySelector<HTMLElement>('.slot-staff-cell.is-roster-shift-open');
                        return cell === null ? null : getComputedStyle(cell).backgroundColor;
                    })(),
                    openShiftFontWeight: (() => {
                        const cell = projection.querySelector<HTMLElement>('.slot-staff-cell.is-roster-shift-open');
                        return cell === null ? null : getComputedStyle(cell).fontWeight;
                    })(),
                });
            });
            observer.observe(document.body, { childList: true });
        }), {
            projectionAttr: rosterImageExportProjectionDomAttr,
            cellAttr: rosterImageExportCellDomAttr,
        });
        const downloadPromise = page.waitForEvent('download');
        await printExportButton.click();
        const [download, exportGeometry] = await Promise.all([downloadPromise, exportGeometryPromise]);

        expect(exportGeometry.dayCellCount).toBe(sourceDayCellCount);
        expect([null, 'none']).toContain(exportGeometry.wageRailDisplay);
        expect(exportGeometry.dayRight).not.toBeNull();
        expect(exportGeometry.firstSlotLeft).not.toBeNull();
        expect(exportGeometry.firstSlotLeft ?? 0).toBeGreaterThanOrEqual((exportGeometry.dayRight ?? 0) - 1);
        expect(exportGeometry.alignedRowCount).toBeGreaterThan(0);
        expect(exportGeometry.dayRailHeaderDisplay).toBe('none');
        expect(exportGeometry.slotHeaderDisplay).toBe('none');
        expect(exportGeometry.lightDayBackground).toBe('rgb(255, 255, 255)');
        expect(exportGeometry.darkDayBackground).toBe('rgb(198, 204, 212)');
        expect(exportGeometry.cellTextAlign).toBe('center');
        expect(exportGeometry.laneBorderWidth).toBe('3px');
        expect(exportGeometry.openShiftBoxShadow).toBe('none');
        expect(exportGeometry.openShiftBackground).toBe('rgba(0, 0, 0, 0)');
        expect(exportGeometry.openShiftFontWeight).toBe('700');

        expect(download.suggestedFilename()).toBe(config.imageExportFilename);
        await expect(printExportButton).toHaveText('Export print PNG');
        const downloadPath = await download.path();
        expect(downloadPath).not.toBeNull();
        const bytes = readFileSync(downloadPath ?? '');
            expect(Array.from(bytes.subarray(0, 8))).toEqual([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
            expect(bytes.length).toBeGreaterThan(1000);

            const colourDownloadPromise = page.waitForEvent('download');
            await colourExportButton.click();
            const colourDownload = await colourDownloadPromise;
            expect(colourDownload.suggestedFilename()).toBe(colourConfig.imageExportFilename);
            await expect(colourExportButton).toHaveText('Export colour PNG');
        } finally {
            await page.reload();
            await expect(page.locator('#roster-week-shell')).toBeVisible();
            if (await publishToggle.isChecked()) await publishToggleRoot.click();
        }
    });

    test('does not show roster PNG exports on Draft windows', async ({ page }) => {
        await openRoster(page, { weekOffset: 2 });

        await openRosterSettings(page);
        await expect(page.getByRole('button', { name: 'Export colour PNG' })).toHaveCount(0);
        await expect(page.getByRole('button', { name: 'Export print PNG' })).toHaveCount(0);
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

        await expect(page.getByRole('button', { name: 'Export colour PNG' })).toHaveCount(0);
        await expect(page.getByRole('button', { name: 'Export print PNG' })).toHaveCount(0);
        await expect(page.getByText('Hide from dropdowns')).toHaveCount(0);
        await expect(page.getByRole('button', { name: 'Sync Slots' })).toHaveCount(0);

        await expect(page.getByRole('button', { name: 'Open roster week overview' })).toHaveCount(0);
        await expect(page.locator(`[${rosterWeekOverviewPanelDomAttr}]`)).toHaveCount(0);
        await expect(page.locator(`[${rosterWeekOverviewDayDomAttr}]`)).toHaveCount(0);
    });
});
