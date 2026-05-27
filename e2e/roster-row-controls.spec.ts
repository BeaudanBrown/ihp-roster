import { test, expect } from '@playwright/test';
import {
    addRowToRosterDay,
    editableRosterRows,
    firstEditableRosterDaySection,
    openRoster,
    removeRowFromRosterDay,
    rosterDayAddButtonForSection,
    rosterDayRemoveButtonForSection,
} from './test-helpers';

async function loginAndOpenRoster(page) {
    await openRoster(page);
}

test.describe('Roster row controls', () => {
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
        await loginAndOpenRoster(page);
        await page.setViewportSize({ width: 1440, height: 900 });

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

            return {
                sidePosition: sideStyle.position,
                sideTop: sideStyle.top,
                panelHeight: Math.round(panel.getBoundingClientRect().height),
                viewportHeight: window.innerHeight,
                panelOverflow: panelStyle.overflowY,
                listOverflow: listStyle.overflowY,
                listScrollable: list.scrollHeight > list.clientHeight,
            };
        });

        expect(sidebarMetrics).not.toBeNull();
        expect(sidebarMetrics?.sidePosition).toBe('sticky');
        expect(sidebarMetrics?.sideTop).not.toBe('auto');
        expect(sidebarMetrics?.panelHeight ?? 0).toBeLessThanOrEqual(sidebarMetrics?.viewportHeight ?? 0);
        expect(sidebarMetrics?.panelOverflow).toBe('hidden');
        expect(sidebarMetrics?.listOverflow).toBe('auto');
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
            const timeTrigger = realCard.querySelector('.slot-time-trigger');
            const staffInput = realCard.querySelector('.slot-cell-input');
            const conflictProbe = document.createElement('div');
            const emptyStaffInput = createCard?.querySelector('.slot-staff-input');
            const emptyShiftTypeInput = createCard?.querySelector('.slot-shift-type-input');
            const emptyTimeLabel = createCard?.querySelector('.roster-shift-card-time .js-time-picker-label');

            if (
                !(column instanceof HTMLElement)
                || !(createCard instanceof HTMLElement)
                || !(fields instanceof HTMLElement)
                || !(timeField instanceof HTMLElement)
                || !(staffField instanceof HTMLElement)
                || !(codeField instanceof HTMLElement)
                || !(typeBadge instanceof HTMLElement)
                || !(timeTrigger instanceof HTMLElement)
                || !(staffInput instanceof HTMLElement)
                || !(emptyStaffInput instanceof HTMLSelectElement)
                || !(emptyShiftTypeInput instanceof HTMLSelectElement)
                || !(emptyTimeLabel instanceof HTMLElement)
            ) {
                return null;
            }

            realCard.classList.remove('conflict-critical', 'conflict-advisory', 'conflict-preference', 'conflict-ideal');
            staffField.classList.remove('conflict-critical', 'conflict-advisory', 'conflict-preference', 'conflict-ideal');
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
            const timeTriggerStyle = getComputedStyle(timeTrigger);
            const staffInputStyle = getComputedStyle(staffInput);
            const conflictProbeStyle = getComputedStyle(conflictProbe);
            const emptyStaffInputStyle = getComputedStyle(emptyStaffInput);
            const emptyShiftTypeInputStyle = getComputedStyle(emptyShiftTypeInput);
            const emptyTimeLabelStyle = getComputedStyle(emptyTimeLabel);

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
                staffColor: staffInputStyle.color,
                cardHasConflictClass: realCard.classList.contains('conflict-critical'),
                conflictBackground: conflictProbeStyle.backgroundColor,
                conflictColor: conflictProbeStyle.color,
                timeTriggerBorderWidth: timeTriggerStyle.borderTopWidth,
                staffInputBorderWidth: staffInputStyle.borderTopWidth,
                emptyStaffText: emptyStaffInput.selectedOptions[0]?.textContent?.trim() ?? '',
                emptyShiftTypeText: emptyShiftTypeInput.selectedOptions[0]?.textContent?.trim() ?? '',
                emptyStaffColor: emptyStaffInputStyle.color,
                emptyShiftTypeColor: emptyShiftTypeInputStyle.color,
                emptyTimeColor: emptyTimeLabelStyle.color,
                emptyShiftTypeTextAlign: emptyShiftTypeInputStyle.textAlign,
                emptyShiftTypeTextAlignLast: emptyShiftTypeInputStyle.textAlignLast,
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
        expect(metrics?.staffColor).toBe(metrics?.conflictColor);
        expect(metrics?.cardHasConflictClass).toBe(false);
        expect(metrics?.timeTriggerBorderWidth).toBe('0px');
        expect(metrics?.staffInputBorderWidth).toBe('0px');
        expect(metrics?.emptyStaffText).toBe('Staff');
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
                        <div class="slot-cell-static">12:00 PM</div>
                    </div>
                    <div class="roster-shift-card-field roster-shift-card-staff">
                        <div class="slot-cell-static">Sonia</div>
                    </div>
                    <div class="roster-shift-card-field roster-shift-card-code">
                        <div class="slot-cell-static roster-shift-type-badge roster-shift-type-badge-readonly">
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
