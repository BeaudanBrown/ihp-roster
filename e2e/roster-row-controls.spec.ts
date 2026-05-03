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

        await page.getByRole('button', { name: 'Roster actions' }).click();
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
            const timeTrigger = realCard.querySelector('.slot-time-trigger');
            const staffInput = realCard.querySelector('.slot-cell-input');
            const conflictProbe = document.createElement('div');

            if (
                !(column instanceof HTMLElement)
                || !(createCard instanceof HTMLElement)
                || !(fields instanceof HTMLElement)
                || !(timeField instanceof HTMLElement)
                || !(staffField instanceof HTMLElement)
                || !(codeField instanceof HTMLElement)
                || !(timeTrigger instanceof HTMLElement)
                || !(staffInput instanceof HTMLElement)
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
            const timeTriggerStyle = getComputedStyle(timeTrigger);
            const staffInputStyle = getComputedStyle(staffInput);
            const conflictProbeStyle = getComputedStyle(conflictProbe);

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
                staffColor: staffInputStyle.color,
                cardHasConflictClass: realCard.classList.contains('conflict-critical'),
                conflictBackground: conflictProbeStyle.backgroundColor,
                conflictColor: conflictProbeStyle.color,
                timeTriggerBorderWidth: timeTriggerStyle.borderTopWidth,
                staffInputBorderWidth: staffInputStyle.borderTopWidth,
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
        expect(metrics?.staffBackground).toBe(metrics?.conflictBackground);
        expect(metrics?.staffColor).toBe(metrics?.conflictColor);
        expect(metrics?.cardHasConflictClass).toBe(false);
        expect(metrics?.timeTriggerBorderWidth).toBe('0px');
        expect(metrics?.staffInputBorderWidth).toBe('0px');
    });
});
