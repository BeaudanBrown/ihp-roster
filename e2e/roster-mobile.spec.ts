import { test, expect, type Page } from '@playwright/test';
import {
    ensureRosterLayout,
    expectContainerToManageHorizontalOverflow,
    expectNoHorizontalViewportOverflow,
    firstRosterDayAddButton,
    firstRosterDayRemoveButton,
    openRoster,
    runSql,
} from './test-helpers';

async function ensureAtLeastTwoRosterColumns(page: Page) {
    const frame = page.locator('.roster-grid-frame').first();
    const slotCount = await frame.evaluate((element) => {
        if (!(element instanceof HTMLElement)) {
            throw new Error('Expected roster frame to be an HTMLElement');
        }
        return Number.parseInt(getComputedStyle(element).getPropertyValue('--roster-slot-count'), 10) || 1;
    });

    if (slotCount > 1) return;

    await page.getByRole('button', { name: 'Edit roster columns' }).click();
    await expect(page.getByRole('button', { name: 'Add roster column' })).toBeVisible();

    const createResponsePromise = page.waitForResponse((response) => {
        return response.request().method() === 'POST' && response.url().includes('/CreateRosterWeekSlotDefinition');
    });
    await page.getByRole('button', { name: 'Add roster column' }).click();
    const createResponse = await createResponsePromise;
    expect(createResponse.status(), await createResponse.text()).toBe(200);

    await expect.poll(async () => {
        return frame.evaluate((element) => {
            if (!(element instanceof HTMLElement)) return 1;
            return Number.parseInt(getComputedStyle(element).getPropertyValue('--roster-slot-count'), 10) || 1;
        });
    }).toBeGreaterThan(1);
}

test.describe('Roster mobile baseline', () => {
    test.beforeEach(async ({ page }) => {
        await openRoster(page);
        await expect(page.locator('#roster-week-shell')).toBeVisible();
        await expect(page.locator('#roster-content')).toBeVisible();
        await expect(page.locator('.roster-grid')).toBeVisible();
    });

    test('keeps the roster shell within the viewport and contains any grid overflow locally', async ({ page }) => {
        await expectNoHorizontalViewportOverflow(page);
        await expectContainerToManageHorizontalOverflow(page, '.roster-slots-scroller');

        const rosterTableMetrics = await page.locator('.roster-grid-frame').first().evaluate((frame) => {
            if (!(frame instanceof HTMLElement)) {
                throw new Error('Expected roster grid frame to be an HTMLElement');
            }

            const scroller = frame.querySelector('.roster-slots-scroller');
            const grid = frame.querySelector('.roster-grid');
            const dayRail = frame.querySelector('.roster-day-rail');
            const daySection = frame.querySelector('.roster-day-rail-section');
            const firstGridSection = frame.querySelector('.roster-grid-day-section');

            if (
                !(scroller instanceof HTMLElement)
                || !(grid instanceof HTMLElement)
                || !(dayRail instanceof HTMLElement)
                || !(daySection instanceof HTMLElement)
                || !(firstGridSection instanceof HTMLElement)
            ) {
                return null;
            }

            const railBefore = dayRail.getBoundingClientRect();
            const scrollerBefore = scroller.getBoundingClientRect();
            scroller.scrollLeft = Math.floor((scroller.scrollWidth - scroller.clientWidth) / 2);
            const railAfter = dayRail.getBoundingClientRect();
            const scrollerAfter = scroller.getBoundingClientRect();

            return {
                scrollerClientWidth: scroller.clientWidth,
                scrollerScrollWidth: scroller.scrollWidth,
                overflowX: getComputedStyle(scroller).overflowX,
                gridMinWidth: getComputedStyle(grid).minWidth,
                slotCount: Number.parseInt(getComputedStyle(frame).getPropertyValue('--roster-slot-count'), 10) || 0,
                dayRailPosition: getComputedStyle(dayRail).position,
                daySectionPosition: getComputedStyle(daySection).position,
                firstDayRailHeight: Math.round(daySection.getBoundingClientRect().height),
                firstGridSectionHeight: Math.round(firstGridSection.getBoundingClientRect().height),
                railLeftBefore: Math.round(railBefore.left),
                railLeftAfter: Math.round(railAfter.left),
                railRightAfter: Math.round(railAfter.right),
                scrollerLeftBefore: Math.round(scrollerBefore.left),
                scrollerLeftAfter: Math.round(scrollerAfter.left),
                cellWidths: Array.from(grid.querySelectorAll('.day-row:first-child > [role="gridcell"]')).map((cell) =>
                    Math.round(cell.getBoundingClientRect().width)
                ),
            };
        });

        expect(rosterTableMetrics).not.toBeNull();
        expect(rosterTableMetrics?.overflowX).toBe('auto');
        expect(rosterTableMetrics?.scrollerScrollWidth).toBeGreaterThanOrEqual(rosterTableMetrics?.scrollerClientWidth ?? 0);
        if ((rosterTableMetrics?.slotCount ?? 0) > 1) {
            expect(rosterTableMetrics?.scrollerScrollWidth).toBeGreaterThan(rosterTableMetrics?.scrollerClientWidth ?? 0);
        }
        expect(rosterTableMetrics?.gridMinWidth).not.toBe('0px');
        expect(rosterTableMetrics?.dayRailPosition).toBe('static');
        expect(rosterTableMetrics?.daySectionPosition).toBe('static');
        expect(rosterTableMetrics?.firstDayRailHeight).toBe(rosterTableMetrics?.firstGridSectionHeight);
        expect(rosterTableMetrics?.railLeftAfter).toBe(rosterTableMetrics?.railLeftBefore);
        expect(rosterTableMetrics?.scrollerLeftAfter).toBe(rosterTableMetrics?.scrollerLeftBefore);
        expect(rosterTableMetrics?.scrollerLeftAfter).toBeGreaterThanOrEqual((rosterTableMetrics?.railRightAfter ?? 0) - 1);
        expect(rosterTableMetrics?.cellWidths.length).toBeGreaterThanOrEqual(3);
        expect(rosterTableMetrics?.cellWidths[1]).toBeGreaterThan(rosterTableMetrics?.cellWidths[0] ?? 0);

        const metrics = await page.evaluate(() => {
            const side = document.querySelector('.roster-layout-side');
            const panel = document.querySelector('.roster-staff-panel');
            const list = document.querySelector('.roster-staff-panel-list');

            if (!(side instanceof HTMLElement) || !(panel instanceof HTMLElement) || !(list instanceof HTMLElement)) {
                return null;
            }

            return {
                sidePosition: getComputedStyle(side).position,
                panelOverflowY: getComputedStyle(panel).overflowY,
                listOverflowY: getComputedStyle(list).overflowY,
            };
        });

        expect(metrics).not.toBeNull();
        expect(metrics?.sidePosition).toBe('static');
        expect(metrics?.panelOverflowY).not.toBe('hidden');
        expect(metrics?.listOverflowY).not.toBe('auto');
    });

    test('keeps the day-row day rail width stable when end times are enabled on phone widths', async ({ page }) => {
        await page.setViewportSize({ width: 390, height: 844 });

        const readMetrics = async () => page.locator('.roster-grid-frame').first().evaluate((frame) => {
            if (!(frame instanceof HTMLElement)) {
                throw new Error('Expected roster frame to be an HTMLElement');
            }

            const rail = frame.querySelector('.roster-day-rail');
            const scroller = frame.querySelector('.roster-slots-scroller');
            if (!(rail instanceof HTMLElement) || !(scroller instanceof HTMLElement)) {
                throw new Error('Expected day-row rail and scroller to be present');
            }

            return {
                endTimes: frame.dataset.rosterEndTimes,
                railWidth: Math.round(rail.getBoundingClientRect().width),
                scrollerWidth: Math.round(scroller.getBoundingClientRect().width),
                slotCount: Number.parseInt(getComputedStyle(frame).getPropertyValue('--roster-slot-count'), 10) || 1,
                scrollerScrollWidth: scroller.scrollWidth,
            };
        });

        runSql("UPDATE venue_config SET roster_end_times_enabled = FALSE WHERE venue_id = 'a1000000-0000-0000-0000-000000000001'");
        await page.reload();
        await expect(page.locator('.roster-grid-frame[data-roster-end-times="false"]')).toBeVisible();
        const withoutEndTimes = await readMetrics();

        runSql("UPDATE venue_config SET roster_end_times_enabled = TRUE WHERE venue_id = 'a1000000-0000-0000-0000-000000000001'");
        await page.reload();
        await expect(page.locator('.roster-grid-frame[data-roster-end-times="true"]')).toBeVisible();
        const withEndTimes = await readMetrics();

        runSql("UPDATE venue_config SET roster_end_times_enabled = FALSE WHERE venue_id = 'a1000000-0000-0000-0000-000000000001'");

        expect(withoutEndTimes.endTimes).toBe('false');
        expect(withEndTimes.endTimes).toBe('true');
        expect(withEndTimes.railWidth).toBe(withoutEndTimes.railWidth);
        expect(withEndTimes.scrollerWidth).toBe(withoutEndTimes.scrollerWidth);
        expect(withEndTimes.scrollerScrollWidth).toBeGreaterThanOrEqual(withEndTimes.scrollerWidth * withEndTimes.slotCount);
    });

    test('snaps horizontal day-row scrolling to one slot group on phone widths', async ({ page }) => {
        await page.setViewportSize({ width: 390, height: 844 });
        await page.emulateMedia({ reducedMotion: 'reduce' });
        await ensureAtLeastTwoRosterColumns(page);

        const snapMetrics = await page.locator('.roster-slots-scroller').first().evaluate(async (scroller) => {
            if (!(scroller instanceof HTMLElement)) {
                throw new Error('Expected roster slot scroller to be an HTMLElement');
            }

            const frame = scroller.closest('.roster-grid-frame');
            if (!(frame instanceof HTMLElement)) {
                throw new Error('Expected roster slot scroller to live in a roster frame');
            }

            const slotCount = Number.parseInt(getComputedStyle(frame).getPropertyValue('--roster-slot-count'), 10) || 1;
            const maxScrollLeft = Math.max(0, scroller.scrollWidth - scroller.clientWidth);
            const groupWidth = scroller.scrollWidth / slotCount;
            const rawScrollLeft = groupWidth * 1.45;
            const expectedScrollLeft = Math.min(Math.max(0, Math.round(rawScrollLeft / groupWidth) * groupWidth), maxScrollLeft);

            scroller.scrollLeft = rawScrollLeft;
            scroller.dispatchEvent(new Event('scroll', { bubbles: false }));

            await new Promise((resolve) => window.setTimeout(resolve, 260));

            return {
                slotCount,
                clientWidth: scroller.clientWidth,
                scrollWidth: scroller.scrollWidth,
                groupWidth,
                expectedScrollLeft,
                actualScrollLeft: scroller.scrollLeft,
                snapType: getComputedStyle(scroller).scrollSnapType,
                dayRailRight: Math.round(frame.querySelector('.roster-day-rail')?.getBoundingClientRect().right ?? 0),
                scrollerLeft: Math.round(scroller.getBoundingClientRect().left),
            };
        });

        expect(snapMetrics.slotCount).toBeGreaterThan(1);
        expect(snapMetrics.scrollWidth).toBeGreaterThan(snapMetrics.clientWidth);
        expect(snapMetrics.snapType).toContain('mandatory');
        expect(Math.abs(snapMetrics.actualScrollLeft - snapMetrics.expectedScrollLeft)).toBeLessThanOrEqual(2);
        expect(snapMetrics.scrollerLeft).toBeGreaterThanOrEqual(snapMetrics.dayRailRight - 1);
    });

    test('waits until pointer release before applying phone horizontal snap', async ({ page }) => {
        await page.setViewportSize({ width: 390, height: 844 });
        await page.emulateMedia({ reducedMotion: 'reduce' });
        await ensureAtLeastTwoRosterColumns(page);

        const snapMetrics = await page.locator('.roster-slots-scroller').first().evaluate(async (scroller) => {
            if (!(scroller instanceof HTMLElement)) {
                throw new Error('Expected roster slot scroller to be an HTMLElement');
            }

            const frame = scroller.closest('.roster-grid-frame');
            if (!(frame instanceof HTMLElement)) {
                throw new Error('Expected roster slot scroller to live in a roster frame');
            }

            const slotCount = Number.parseInt(getComputedStyle(frame).getPropertyValue('--roster-slot-count'), 10) || 1;
            const groupWidth = scroller.scrollWidth / slotCount;
            const rawScrollLeft = groupWidth * 0.42;
            const expectedScrollLeft = Math.round(rawScrollLeft / groupWidth) * groupWidth;

            scroller.dispatchEvent(new PointerEvent('pointerdown', {
                bubbles: true,
                pointerId: 101,
                pointerType: 'touch',
            }));
            scroller.scrollLeft = rawScrollLeft;
            scroller.dispatchEvent(new Event('scroll', { bubbles: false }));

            await new Promise((resolve) => window.setTimeout(resolve, 260));
            const duringPointerScrollLeft = scroller.scrollLeft;
            const snapTypeDuringPointer = getComputedStyle(scroller).scrollSnapType;
            const draggingDuringPointer = scroller.dataset.horizontalSnapDragging;

            scroller.dispatchEvent(new PointerEvent('pointerup', {
                bubbles: true,
                pointerId: 101,
                pointerType: 'touch',
            }));
            await new Promise((resolve) => window.setTimeout(resolve, 260));

            return {
                rawScrollLeft,
                expectedScrollLeft,
                duringPointerScrollLeft,
                finalScrollLeft: scroller.scrollLeft,
                snapTypeDuringPointer,
                draggingDuringPointer,
                draggingAfterPointer: scroller.dataset.horizontalSnapDragging ?? '',
            };
        });

        expect(Math.abs(snapMetrics.duringPointerScrollLeft - snapMetrics.rawScrollLeft)).toBeLessThanOrEqual(2);
        expect(snapMetrics.snapTypeDuringPointer).toBe('none');
        expect(snapMetrics.draggingDuringPointer).toBe('true');
        expect(snapMetrics.draggingAfterPointer).toBe('');
        expect(Math.abs(snapMetrics.finalScrollLeft - snapMetrics.expectedScrollLeft)).toBeLessThanOrEqual(2);
    });

    test('snaps horizontal day-column scrolling to the nearest centered day on phone widths', async ({ page }) => {
        await page.setViewportSize({ width: 390, height: 844 });
        await page.emulateMedia({ reducedMotion: 'reduce' });
        await ensureRosterLayout(page, 'day_columns');
        await expect(page.locator('.roster-day-columns')).toBeVisible();

        const snapMetrics = await page.locator('.roster-grid-frame[data-roster-layout="day_columns"]').first().evaluate(async (frame) => {
            if (!(frame instanceof HTMLElement)) {
                throw new Error('Expected day-column roster frame to be an HTMLElement');
            }

            const columnsContainer = frame.querySelector('.roster-day-columns');
            if (!(columnsContainer instanceof HTMLElement)) {
                throw new Error('Expected day-column roster frame to contain day columns');
            }

            while (columnsContainer.querySelectorAll('.roster-day-column').length < 3) {
                const firstColumn = columnsContainer.querySelector('.roster-day-column');
                if (!(firstColumn instanceof HTMLElement)) {
                    throw new Error('Expected at least one rendered day column');
                }
                columnsContainer.appendChild(firstColumn.cloneNode(true));
            }
            columnsContainer.style.setProperty('--roster-day-count', String(columnsContainer.querySelectorAll('.roster-day-column').length));

            const columns = Array.from(frame.querySelectorAll('.roster-day-column')).filter((column): column is HTMLElement => column instanceof HTMLElement);
            const maxScrollLeft = Math.max(0, frame.scrollWidth - frame.clientWidth);
            const secondColumnTarget = columns[1].offsetLeft + (columns[1].offsetWidth / 2) - (frame.clientWidth / 2);
            const rawScrollLeft = Math.min(Math.max(0, secondColumnTarget - (columns[1].offsetWidth * 0.32)), maxScrollLeft);

            frame.scrollLeft = rawScrollLeft;
            const frameRectBeforeSnap = frame.getBoundingClientRect();
            const secondColumnRectBeforeSnap = columns[1].getBoundingClientRect();
            const expectedScrollLeft = Math.min(
                Math.max(
                    0,
                    frame.scrollLeft
                        + (secondColumnRectBeforeSnap.left + (secondColumnRectBeforeSnap.width / 2))
                        - (frameRectBeforeSnap.left + (frameRectBeforeSnap.width / 2)),
                ),
                maxScrollLeft,
            );
            frame.dispatchEvent(new Event('scroll', { bubbles: false }));

            await new Promise((resolve) => window.setTimeout(resolve, 260));

            const frameRect = frame.getBoundingClientRect();
            const frameCenter = frameRect.left + (frameRect.width / 2);
            const nearestColumn = columns.reduce((nearest, column) => {
                const columnRect = column.getBoundingClientRect();
                const columnCenter = columnRect.left + (columnRect.width / 2);
                const distance = Math.abs(columnCenter - frameCenter);
                if (!nearest || distance < nearest.distance) {
                    return { index: columns.indexOf(column), distance, centerOffset: columnCenter - frameCenter };
                }
                return nearest;
            }, null as null | { index: number; distance: number; centerOffset: number });

            return {
                columnCount: columns.length,
                clientWidth: frame.clientWidth,
                scrollWidth: frame.scrollWidth,
                maxScrollLeft,
                expectedScrollLeft,
                actualScrollLeft: frame.scrollLeft,
                nearestIndex: nearestColumn?.index ?? -1,
                nearestCenterOffset: nearestColumn?.centerOffset ?? Number.NaN,
                snapType: getComputedStyle(frame).scrollSnapType,
                columnSnapAlign: getComputedStyle(columns[1]).scrollSnapAlign,
            };
        });

        expect(snapMetrics).not.toBeNull();
        expect(snapMetrics?.columnCount).toBeGreaterThan(1);
        expect(snapMetrics?.scrollWidth).toBeGreaterThan(snapMetrics?.clientWidth ?? 0);
        expect(snapMetrics?.snapType).toContain('mandatory');
        expect(snapMetrics?.columnSnapAlign).toBe('center');
        expect(snapMetrics?.nearestIndex).toBe(1);
        expect(Math.abs((snapMetrics?.actualScrollLeft ?? 0) - (snapMetrics?.expectedScrollLeft ?? 0))).toBeLessThanOrEqual(2);
        expect(Math.abs(snapMetrics?.nearestCenterOffset ?? 0)).toBeLessThanOrEqual(8);
    });

    test('keeps day-column closed controls stable on phone widths', async ({ page }) => {
        await page.setViewportSize({ width: 390, height: 844 });
        await ensureRosterLayout(page, 'day_columns');

        const firstColumn = page.locator('.roster-day-column').first();
        const closeButton = firstColumn.locator('[data-roster-day-closed-toggle="true"]');
        await expect(closeButton).toBeVisible();

        const readMetrics = async () => firstColumn.evaluate((column) => {
            if (!(column instanceof HTMLElement)) {
                throw new Error('Expected roster day column to be an HTMLElement');
            }

            const header = column.querySelector('.roster-day-column-header');
            const controlSlot = column.querySelector('.roster-day-column-control-slot');
            const toggle = column.querySelector('[data-roster-day-closed-toggle="true"]');
            if (!(header instanceof HTMLElement) || !(controlSlot instanceof HTMLElement) || !(toggle instanceof HTMLElement)) {
                throw new Error('Expected day-column header controls');
            }

            const headerRect = header.getBoundingClientRect();
            const slotRect = controlSlot.getBoundingClientRect();
            const toggleRect = toggle.getBoundingClientRect();

            return {
                headerHeight: Math.round(headerRect.height),
                slotLeft: Math.round(slotRect.left),
                slotRight: Math.round(slotRect.right),
                slotWidth: Math.round(slotRect.width),
                toggleLeft: Math.round(toggleRect.left),
                toggleRight: Math.round(toggleRect.right),
                toggleWidth: Math.round(toggleRect.width),
                bodyScrollWidth: document.body.scrollWidth,
                viewportWidth: document.documentElement.clientWidth,
            };
        });

        const before = await readMetrics();
        await closeButton.click();
        await expect(firstColumn.locator('[data-roster-day-closed-toggle="true"]')).toContainText('CLOSED');
        const closed = await readMetrics();
        await firstColumn.locator('[data-roster-day-closed-toggle="true"]').click();
        await expect(firstColumn.locator('[data-roster-day-closed-toggle="true"] .bi-unlock')).toBeVisible();
        const reopened = await readMetrics();

        expect(closed.headerHeight).toBe(before.headerHeight);
        expect(closed.slotLeft).toBe(before.slotLeft);
        expect(closed.slotRight).toBe(before.slotRight);
        expect(closed.slotWidth).toBe(before.slotWidth);
        expect(closed.toggleLeft).toBe(before.toggleLeft);
        expect(closed.toggleRight).toBe(before.toggleRight);
        expect(closed.toggleWidth).toBe(before.toggleWidth);
        expect(reopened.slotLeft).toBe(before.slotLeft);
        expect(reopened.toggleWidth).toBe(before.toggleWidth);
        expect(closed.bodyScrollWidth).toBeLessThanOrEqual(closed.viewportWidth + 1);
        await expectNoHorizontalViewportOverflow(page);
    });

    test('preserves core week navigation and row controls on a narrow viewport', async ({ page }) => {
        await expect(firstRosterDayAddButton(page)).toBeVisible();
        await expect(firstRosterDayRemoveButton(page)).toBeVisible();

        const shell = page.locator('#roster-week-shell');
        const initialShellHtml = await shell.evaluate((el) => el.outerHTML);

        const nextWeekButton = page.getByRole('link', { name: 'Next week' });
        await nextWeekButton.click();
        await expect(shell).toBeVisible();
        const nextShellHtml = await shell.evaluate((el) => el.outerHTML);
        expect(nextShellHtml).not.toBe(initialShellHtml);
        await expectNoHorizontalViewportOverflow(page);
    });

    test('uses compact closed-day controls without add or remove actions', async ({ page }) => {
        const firstDayRailSection = page.locator('.roster-day-rail-section').first();
        const firstSlotDaySection = page.locator('[data-roster-day-section="true"]').first();
        const closeButton = firstDayRailSection.locator('[data-roster-day-closed-toggle="true"]');

        await expect(closeButton).toBeVisible();
        await expect(closeButton.locator('.bi-unlock')).toBeVisible();
        await expect(firstDayRailSection.locator('[data-roster-day-add="true"]')).toBeVisible();
        await expect(firstDayRailSection.locator('[data-roster-day-remove="true"]')).toBeVisible();

        await closeButton.click();

        const reopenButton = firstDayRailSection.locator('[data-roster-day-closed-toggle="true"]');
        await expect(reopenButton).toContainText('CLOSED');
        await expect(reopenButton.locator('.bi-lock-fill')).toBeVisible();
        await expect(firstDayRailSection.locator('[data-roster-day-add="true"]')).toHaveCount(0);
        await expect(firstDayRailSection.locator('[data-roster-day-remove="true"]')).toHaveCount(0);
        await expect(firstSlotDaySection.locator('[data-roster-row]')).toHaveCount(2);

        await reopenButton.click();
        await expect(firstDayRailSection.locator('[data-roster-day-add="true"]')).toBeVisible();
    });

    test('keeps roster shift launchers reachable without requiring the staff sidebar first', async ({ page }) => {
        const launchers = page.locator('[data-roster-shift-launcher="true"]');
        await expect(launchers.first()).toBeVisible();

        const sampleCount = Math.min(await launchers.count(), 3);
        for (let index = 0; index < sampleCount; index += 1) {
            const launcher = launchers.nth(index);
            await launcher.scrollIntoViewIfNeeded();

            const reachable = await launcher.evaluate((element) => {
                if (!(element instanceof HTMLElement)) {
                    throw new Error('Expected roster launcher to be an HTMLElement');
                }

                const scroller = element.closest('.roster-slots-scroller');
                if (!(scroller instanceof HTMLElement)) {
                    throw new Error('Expected roster launcher to live in the slot scroller');
                }

                element.scrollIntoView({ block: 'nearest', inline: 'center' });
                const rect = element.getBoundingClientRect();
                const scrollerRect = scroller.getBoundingClientRect();
                const visibleLeft = Math.max(rect.left, scrollerRect.left, 0);
                const visibleRight = Math.min(rect.right, scrollerRect.right, window.innerWidth);

                return {
                    visibleWidth: Math.round(Math.max(0, visibleRight - visibleLeft)),
                };
            });

            expect(reachable.visibleWidth).toBeGreaterThan(20);
            await expectNoHorizontalViewportOverflow(page);
        }
    });
});
