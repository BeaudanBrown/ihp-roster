import { test, expect, type Page } from '@playwright/test';
import {
    addRowToRosterDay,
    editableRosterRows,
    firstEditableRosterDaySection,
    openRoster,
    removeRowFromRosterDay,
    rosterDayAddButtonForSection,
    rosterDayRemoveButtonForSection,
} from './test-helpers';

async function loginAndOpenRoster(page: Page) {
    await openRoster(page);
}

test.describe('Roster row controls', () => {
    test('labels the single time column as start in day-row mode', async ({ page }) => {
        await loginAndOpenRoster(page);
        await expect(page.locator('.roster-grid-frame[data-roster-layout="day_rows"][data-roster-end-times="false"]')).toBeVisible();

        const subheaders = page.locator('.roster-slots-scroller .roster-grid-header-row-subheads .roster-subhead');
        await expect(subheaders.first()).toHaveText('Start');
        await expect(subheaders.filter({ hasText: /^Time$/ })).toHaveCount(0);
    });

    test('adds and removes the last row from the day header controls', async ({ page }) => {
        await loginAndOpenRoster(page);

        const daySectionId = await firstEditableRosterDaySection(page).getAttribute('id');
        expect(daySectionId).toBeTruthy();

        const daySection = page.locator(`#${daySectionId}`);
        const dayRows = editableRosterRows(daySection);
        let baselineRowCount = await dayRows.count();

        if (baselineRowCount < 2) {
            await addRowToRosterDay(daySection);
            await expect(dayRows).toHaveCount(baselineRowCount + 1);
            baselineRowCount += 1;
        }

        await expect(await rosterDayAddButtonForSection(daySection)).toBeVisible();
        await addRowToRosterDay(daySection);
        await expect(dayRows).toHaveCount(baselineRowCount + 1);

        await expect(await rosterDayRemoveButtonForSection(daySection)).toBeEnabled();
        await removeRowFromRosterDay(daySection);
        await expect(dayRows).toHaveCount(baselineRowCount);
    });

    test('keeps the staff panel sticky, viewport-capped, and internally scrollable', async ({ page }) => {
        await page.setViewportSize({ width: 1440, height: 700 });
        await loginAndOpenRoster(page);

        await page.evaluate(() => {
            const content = document.querySelector('#roster-content');
            const list = document.querySelector('.roster-staff-panel-list');
            const tableBody = document.querySelector('.roster-staff-table-body');

            if (!(content instanceof HTMLElement) || !(list instanceof HTMLElement) || !(tableBody instanceof HTMLElement)) {
                return;
            }

            const spacer = document.createElement('div');
            spacer.setAttribute('data-testid', 'roster-sticky-scroll-spacer');
            spacer.style.height = '1600px';
            spacer.style.pointerEvents = 'none';
            content.appendChild(spacer);

            const sourceRows = Array.from(tableBody.querySelectorAll('tr'));
            for (let index = 0; index < 80 && list.scrollHeight <= list.clientHeight + 100; index += 1) {
                const sourceRow = sourceRows[index % sourceRows.length];
                if (!(sourceRow instanceof HTMLElement)) break;

                const clone = sourceRow.cloneNode(true);
                if (clone instanceof HTMLElement) {
                    clone.setAttribute('aria-hidden', 'true');
                    clone.removeAttribute('hx-get');
                    clone.removeAttribute('tabindex');
                    tableBody.appendChild(clone);
                }
            }
        });

        const initialMetrics = await page.evaluate(() => {
            const side = document.querySelector('.roster-layout-side');
            const main = document.querySelector('.roster-layout-main');

            if (!(side instanceof HTMLElement) || !(main instanceof HTMLElement)) {
                return null;
            }

            return {
                mainRight: Math.round(main.getBoundingClientRect().right),
                sideLeft: Math.round(side.getBoundingClientRect().left),
            };
        });

        expect(initialMetrics).not.toBeNull();
        expect(initialMetrics?.sideLeft ?? 0).toBeGreaterThanOrEqual(initialMetrics?.mainRight ?? 0);

        await page.evaluate(() => window.scrollTo(0, 650));
        await expect.poll(() => page.evaluate(() => window.scrollY)).toBeGreaterThan(600);

        const sidebarMetrics = await page.evaluate(() => {
            const side = document.querySelector('.roster-layout-side');
            const panel = document.querySelector('.roster-staff-panel');
            const list = document.querySelector('.roster-staff-panel-list');

            if (!(side instanceof HTMLElement) || !(panel instanceof HTMLElement) || !(list instanceof HTMLElement)) {
                return null;
            }

            const sideStyle = getComputedStyle(side);
            const panelStyle = getComputedStyle(panel);
            const listStyle = getComputedStyle(list);
            const stickyTop = Number.parseFloat(sideStyle.top);
            const sideRect = side.getBoundingClientRect();
            const panelRect = panel.getBoundingClientRect();

            list.scrollTop = 0;
            list.scrollTop = 96;

            return {
                sidePosition: sideStyle.position,
                sideTop: Math.round(sideRect.top),
                sideStickyTop: Math.round(stickyTop),
                panelHeight: Math.round(panelRect.height),
                panelBottom: Math.round(panelRect.bottom),
                viewportHeight: window.innerHeight,
                panelOverflow: panelStyle.overflowY,
                listOverflow: listStyle.overflowY,
                listClientHeight: list.clientHeight,
                listScrollHeight: list.scrollHeight,
                listScrollTop: list.scrollTop,
            };
        });

        expect(sidebarMetrics).not.toBeNull();
        expect(sidebarMetrics?.sidePosition).toBe('sticky');
        expect(Math.abs((sidebarMetrics?.sideTop ?? 0) - (sidebarMetrics?.sideStickyTop ?? 0))).toBeLessThanOrEqual(1);
        expect(sidebarMetrics?.panelHeight ?? 0).toBeLessThanOrEqual(sidebarMetrics?.viewportHeight ?? 0);
        expect(sidebarMetrics?.panelBottom ?? 0).toBeLessThanOrEqual(sidebarMetrics?.viewportHeight ?? 0);
        expect(sidebarMetrics?.panelOverflow).toBe('hidden');
        expect(sidebarMetrics?.listOverflow).toBe('auto');
        expect(sidebarMetrics?.listScrollHeight ?? 0).toBeGreaterThan(sidebarMetrics?.listClientHeight ?? 0);
        expect(sidebarMetrics?.listScrollTop ?? 0).toBeGreaterThan(0);
    });

    test('clips day-column cards and carries conflict color across all compact controls', async ({ page }) => {
        await loginAndOpenRoster(page);
        await page.setViewportSize({ width: 1280, height: 900 });

        await page.getByRole('button', { name: 'Roster settings' }).click();
        await page.locator('label[for="roster-layout-mode-day_columns"]').click();
        await expect(page.locator('.roster-day-columns')).toBeVisible();

        const metrics = await page.evaluate(() => {
            const realCard = Array.from(document.querySelectorAll('.roster-shift-card'))
                .find((card) => !card.classList.contains('roster-shift-card-create'));
            if (!(realCard instanceof HTMLElement)) {
                return null;
            }

            const column = document.querySelector('.roster-day-column');
            const createCard = document.querySelector('.roster-shift-card-create');
            const fields = realCard.querySelector('.roster-shift-card-fields');
            const timeField = realCard.querySelector('.roster-shift-card-time');
            const staffField = realCard.querySelector('.roster-shift-card-staff');
            const codeField = realCard.querySelector('.roster-shift-card-code');
            const typeBadge = realCard.querySelector('.roster-shift-type-badge');
            const timeStatic = realCard.querySelector('.roster-shift-card-time .slot-cell-static');
            const staffStatic = realCard.querySelector('.roster-shift-card-staff .slot-cell-static');
            const conflictProbe = document.createElement('div');
            const emptyStaffStatic = createCard?.querySelector('.roster-shift-card-staff .slot-cell-static');
            const emptyShiftTypeBadge = createCard?.querySelector('.roster-shift-type-badge');
            const emptyTimeStatic = createCard?.querySelector('.roster-shift-card-time .slot-cell-static');

            if (
                !(column instanceof HTMLElement)
                || !(createCard instanceof HTMLElement)
                || !(fields instanceof HTMLElement)
                || !(timeField instanceof HTMLElement)
                || !(staffField instanceof HTMLElement)
                || !(codeField instanceof HTMLElement)
                || !(typeBadge instanceof HTMLElement)
                || !(timeStatic instanceof HTMLElement)
                || !(staffStatic instanceof HTMLElement)
                || !(emptyStaffStatic instanceof HTMLElement)
                || !(emptyShiftTypeBadge instanceof HTMLElement)
                || !(emptyTimeStatic instanceof HTMLElement)
            ) {
                return null;
            }

            realCard.classList.remove('conflict-critical', 'conflict-preference', 'conflict-ideal');
            staffField.classList.remove('conflict-critical', 'conflict-preference', 'conflict-ideal');
            staffField.classList.add('conflict-critical');

            conflictProbe.className = 'conflict-critical';
            conflictProbe.style.position = 'absolute';
            conflictProbe.style.left = '-9999px';
            document.body.appendChild(conflictProbe);

            const columnStyle = getComputedStyle(column);
            const createStyle = getComputedStyle(createCard);
            const fieldsStyle = getComputedStyle(fields);
            const timeStyle = getComputedStyle(timeField);
            const staffStyle = getComputedStyle(staffField);
            const codeStyle = getComputedStyle(codeField);
            const typeBadgeStyle = getComputedStyle(typeBadge);
            const timeStaticStyle = getComputedStyle(timeStatic);
            const staffStaticStyle = getComputedStyle(staffStatic);
            const conflictProbeStyle = getComputedStyle(conflictProbe);
            const emptyStaffStaticStyle = getComputedStyle(emptyStaffStatic);
            const emptyShiftTypeBadgeStyle = getComputedStyle(emptyShiftTypeBadge);
            const emptyTimeStaticStyle = getComputedStyle(emptyTimeStatic);

            const metrics = {
                columnOverflow: columnStyle.overflow,
                columnRadius: columnStyle.borderRadius,
                createDisplay: createStyle.display,
                createHasEmptyClass: createCard.classList.contains('roster-shift-card-empty'),
                fieldsOverflow: fieldsStyle.overflow,
                fieldsRadius: fieldsStyle.borderRadius,
                timeBackground: timeStyle.backgroundColor,
                staffBackground: staffStyle.backgroundColor,
                codeBackground: codeStyle.backgroundColor,
                badgeDisplay: typeBadgeStyle.display,
                staffColor: staffStaticStyle.color,
                timeFontSize: timeStaticStyle.fontSize,
                staffFontSize: staffStaticStyle.fontSize,
                shiftTypeFontSize: typeBadgeStyle.fontSize,
                cardHasConflictClass: realCard.classList.contains('conflict-critical'),
                conflictBackground: conflictProbeStyle.backgroundColor,
                conflictColor: conflictProbeStyle.color,
                timeStaticBorderWidth: timeStaticStyle.borderTopWidth,
                staffStaticBorderWidth: staffStaticStyle.borderTopWidth,
                emptyStaffText: emptyStaffStatic.textContent?.trim() ?? '',
                emptyShiftTypeText: emptyShiftTypeBadge.textContent?.trim() ?? '',
                emptyStaffColor: emptyStaffStaticStyle.color,
                emptyShiftTypeColor: emptyShiftTypeBadgeStyle.color,
                emptyTimeColor: emptyTimeStaticStyle.color,
                emptyShiftTypeTextAlign: emptyShiftTypeBadgeStyle.textAlign,
                emptyShiftTypeTextAlignLast: emptyShiftTypeBadgeStyle.textAlignLast,
            };

            conflictProbe.remove();
            return metrics;
        });

        expect(metrics).not.toBeNull();
        expect(metrics?.columnOverflow).toBe('hidden');
        expect(metrics?.columnRadius).not.toBe('0px');
        expect(metrics?.createDisplay).toBe('block');
        expect(metrics?.createHasEmptyClass).toBe(false);
        expect(metrics?.fieldsOverflow).toBe('hidden');
        expect(metrics?.fieldsRadius).not.toBe('0px');
        expect(metrics?.timeBackground).toBe(metrics?.codeBackground);
        expect(metrics?.timeBackground).not.toBe(metrics?.conflictBackground);
        expect(metrics?.badgeDisplay).toBe('flex');
        expect(metrics?.staffBackground).toBe(metrics?.conflictBackground);
        expect(metrics?.timeFontSize).toBe(metrics?.staffFontSize);
        expect(metrics?.timeFontSize).toBe(metrics?.shiftTypeFontSize);
        expect(metrics?.cardHasConflictClass).toBe(false);
        expect(metrics?.timeStaticBorderWidth).toBe('0px');
        expect(metrics?.staffStaticBorderWidth).toBe('0px');
        expect(metrics?.emptyStaffText).toBe('Add shift');
        expect(metrics?.emptyShiftTypeText).toBe('Type');
        expect(metrics?.emptyStaffColor).toBe(metrics?.emptyTimeColor);
        expect(metrics?.emptyShiftTypeColor).toBe(metrics?.emptyTimeColor);
        expect(metrics?.emptyShiftTypeTextAlign).toBe('center');
        expect(metrics?.emptyShiftTypeTextAlignLast).toBe('center');
    });

    test('centres read-only day-column names and keeps times on one line', async ({ page }) => {
        await page.setViewportSize({ width: 1280, height: 900 });
        await loginAndOpenRoster(page);

        await page.getByRole('button', { name: 'Roster settings' }).click();
        await page.locator('label[for="roster-layout-mode-day_columns"]').click();
        await expect(page.locator('.roster-day-columns')).toBeVisible();

        const metrics = await page.evaluate(() => {
            const frame = document.querySelector('.roster-grid-frame[data-roster-layout="day_columns"]');
            if (!(frame instanceof HTMLElement)) {
                return null;
            }

            const probe = document.createElement('article');
            probe.className = 'roster-shift-card';
            probe.style.position = 'absolute';
            probe.style.left = '-10000px';
            probe.innerHTML = `
                <div class="roster-shift-card-fields">
                    <div class="roster-shift-card-field roster-shift-card-time">
                        <div class="app-dense-static slot-cell-static">12:00 PM</div>
                    </div>
                    <div class="roster-shift-card-field roster-shift-card-staff">
                        <div class="app-dense-static slot-cell-static">Sonia</div>
                    </div>
                    <div class="roster-shift-card-field roster-shift-card-code">
                        <div class="app-dense-static slot-cell-static roster-shift-type-badge roster-shift-type-badge-readonly">
                            <span class="roster-shift-type-badge-label">Kitchen</span>
                        </div>
                    </div>
                </div>`;
            frame.appendChild(probe);

            const timeCell = probe.querySelector('.roster-shift-card-time .slot-cell-static');
            const staffCell = probe.querySelector('.roster-shift-card-staff .slot-cell-static');
            if (!(timeCell instanceof HTMLElement) || !(staffCell instanceof HTMLElement)) {
                probe.remove();
                return null;
            }

            const timeStyle = getComputedStyle(timeCell);
            const staffStyle = getComputedStyle(staffCell);

            const metrics = {
                timeText: timeCell.textContent?.trim() ?? '',
                timeDisplay: timeStyle.display,
                timeAlignItems: timeStyle.alignItems,
                timeJustifyContent: timeStyle.justifyContent,
                timeWhiteSpace: timeStyle.whiteSpace,
                timeScrollWidth: timeCell.scrollWidth,
                timeClientWidth: timeCell.clientWidth,
                staffDisplay: staffStyle.display,
                staffAlignItems: staffStyle.alignItems,
                staffJustifyContent: staffStyle.justifyContent,
                staffWhiteSpace: staffStyle.whiteSpace,
            };

            probe.remove();
            return metrics;
        });

        expect(metrics).not.toBeNull();
        expect(metrics?.timeText).not.toBe('');
        expect(metrics?.timeDisplay).toBe('flex');
        expect(metrics?.timeAlignItems).toBe('center');
        expect(metrics?.timeJustifyContent).toBe('center');
        expect(metrics?.timeWhiteSpace).toBe('nowrap');
        expect(metrics?.timeScrollWidth ?? 0).toBeLessThanOrEqual((metrics?.timeClientWidth ?? 0) + 1);
        expect(metrics?.staffDisplay).toBe('flex');
        expect(metrics?.staffAlignItems).toBe('center');
        expect(metrics?.staffJustifyContent).toBe('center');
        expect(metrics?.staffWhiteSpace).toBe('nowrap');
    });
});
