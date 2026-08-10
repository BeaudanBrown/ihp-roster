import { test, expect, type Locator, type Page } from '@playwright/test';
import { rosterStaffPanelTabDomAttr } from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from './timeouts';
import {
    addRowToRosterDay,
    editableRosterRows,
    assignRosterShiftStaff,
    existingRosterShiftLaunchers,
    firstEditableRosterDaySection,
    gotoWhenReady,
    openAdminWithSeededPasskeySession,
    openRoster,
    openRosterSettings,
    removeRowFromRosterDay,
    rosterDayAddButtonForSection,
    rosterDayRemoveButtonForSection,
    rosterShiftLaunchers,
} from './test-helpers';

async function loginAndOpenRoster(page: Page) {
    await openRoster(page);
}

async function expectReliableEndEllipsis(label: Locator, fullLabel: string) {
    const metrics = await label.evaluate((element) => {
        if (!(element instanceof HTMLElement)) throw new Error('Expected an HTML shift-type label');
        const style = getComputedStyle(element);
        return {
            display: style.display,
            overflow: style.overflow,
            textOverflow: style.textOverflow,
            whiteSpace: style.whiteSpace,
            title: element.title,
            text: element.textContent,
            clientWidth: element.clientWidth,
            scrollWidth: element.scrollWidth,
        };
    });

    expect(metrics.display).toBe('block');
    expect(metrics.overflow).toBe('hidden');
    expect(metrics.textOverflow).toBe('ellipsis');
    expect(metrics.whiteSpace).toBe('nowrap');
    expect(metrics.title).toBe(fullLabel);
    expect(metrics.text).toBe(fullLabel);
    expect(metrics.clientWidth).toBeGreaterThan(20);
    expect(metrics.scrollWidth).toBeGreaterThan(metrics.clientWidth);
}

test.describe('Roster row controls', () => {
    test('applies scoped reliable end ellipsis to long row-grid and day-column shift labels', async ({ browser, page }) => {
        const fullLabel = 'Front of House Supervisor and Closing Coordinator for Private Functions and Special Events';
        await loginAndOpenRoster(page);

        const rowLabel = page.locator('.roster-grid .slot-shift-type-cell .roster-shift-type-label').first();
        await expect(rowLabel).toBeVisible();
        for (const width of [1280, 390]) {
            await page.setViewportSize({ width, height: 900 });
            await expectReliableEndEllipsis(rowLabel, fullLabel);
        }

        await page.setViewportSize({ width: 1280, height: 900 });
        await openRosterSettings(page);
        await page.locator('label[for="roster-layout-mode-day_columns"]').click();
        const dayColumnLabel = page.locator('.roster-day-columns .roster-shift-type-badge-label').filter({ hasText: fullLabel }).first();
        for (const width of [1280, 390]) {
            await page.setViewportSize({ width, height: 900 });
            await expect(dayColumnLabel).toBeVisible();
            await expectReliableEndEllipsis(dayColumnLabel, fullLabel);
        }

        const rosterUrl = new URL(page.url());
        await gotoWhenReady(
            page,
            `/ShowRosterWindow?${new URLSearchParams({
                anchorDate: rosterUrl.searchParams.get('anchorDate') ?? '',
                rosterGroupId: rosterUrl.searchParams.get('rosterGroupId') ?? '',
                rosterView: 'timeline',
                dayDate: rosterUrl.searchParams.get('anchorDate') ?? '',
            }).toString()}`,
            '.roster-day-timeline',
        );
        await page.setViewportSize({ width: 390, height: 900 });
        const timelineLabel = page.locator('.roster-day-timeline-shift-role').filter({ hasText: fullLabel }).first();
        await expect(timelineLabel).toBeVisible();
        await expectReliableEndEllipsis(timelineLabel, fullLabel);

        const adminContext = await browser.newContext();
        const adminPage = await adminContext.newPage();
        try {
            await openAdminWithSeededPasskeySession(adminPage);
            const nonRosterInput = adminPage.locator('input[value="Front of House Supervisor and Closing Coordinator for Private Functions and Special Events"]');
            await expect(nonRosterInput).toHaveCount(1);
            await expect(nonRosterInput).toHaveValue(fullLabel);
        } finally {
            await adminContext.close();
        }
    });
    test('hosts typed roster settings in the staff panel second tab', async ({ page }) => {
        const tabSetBoundaryErrors: string[] = [];
        page.on('console', (message) => {
            if (message.type() === 'error' && message.text().includes('Invalid generated Surface tab-set boundary')) {
                tabSetBoundaryErrors.push(message.text());
            }
        });

        await loginAndOpenRoster(page);

        const toolbar = page.locator('[data-week-toolbar="roster"]');
        await expect(toolbar.getByRole('button', { name: 'Roster settings' })).toHaveCount(0);

        const staffTab = page.getByRole('tab', { name: 'Staff', exact: true });
        const settingsTab = page.getByRole('tab', { name: 'Settings', exact: true });
        await expect(staffTab).toHaveAttribute('aria-selected', 'true');
        await expect(settingsTab).toHaveAttribute('aria-selected', 'false');
        await expect(staffTab).toHaveAttribute(rosterStaffPanelTabDomAttr, 'staff');
        await expect(settingsTab).toHaveAttribute(rosterStaffPanelTabDomAttr, 'settings');
        expect(await staffTab.evaluate((element) => element.closest('[data-bepis-surface]')?.getAttribute('data-bepis-surface'))).toBe('roster');

        const settingsPane = page.locator('#roster-staff-panel-settings-pane');
        await expect(async () => {
            if (await settingsTab.getAttribute('aria-selected') !== 'true' || !(await settingsPane.isVisible())) {
                await settingsTab.click();
            }
            await expect(settingsTab).toHaveAttribute('aria-selected', 'true');
            await expect(settingsPane).toBeVisible();
        }).toPass({ timeout: E2E_TIMEOUT.assertion });
        await expect(settingsPane.getByRole('heading', { name: 'Roster layout' })).toBeVisible();
        await expect(settingsPane.getByRole('heading', { name: 'Display' })).toBeVisible();
        await expect(settingsPane.getByRole('heading', { name: 'Prevent assignment' })).toBeVisible();
        await expect(settingsPane.locator('[data-bepis-activation-ref]')).toHaveCount(2);
        expect(await settingsPane.locator('form[data-bepis-surface-action]').count()).toBeGreaterThanOrEqual(3);

        const originalStaffPanel = await page.locator('#roster-staff-panel-fragment').elementHandle();
        if (originalStaffPanel === null) throw new Error('Expected original roster staff panel');
        const fragmentSettled = page.evaluate((timeoutMs) => new Promise<void>((resolve, reject) => {
            const timeout = window.setTimeout(() => reject(new Error('Timed out waiting for htmx:afterSettle')), timeoutMs);
            document.addEventListener('htmx:afterSettle', () => {
                window.clearTimeout(timeout);
                resolve();
            }, { once: true });
        }), E2E_TIMEOUT.assertion);
        const fragmentResponse = page.waitForResponse((response) => response.url().includes('/ShowRosterWeekStaffPanelFragment'));
        await settingsPane.evaluate((pane) => {
            const actionForm = pane.querySelector('form[action*="CopyRosterWeek"]');
            if (!(actionForm instanceof HTMLFormElement)) throw new Error('Expected roster week action form');
            const actionUrl = new URL(actionForm.action);
            const currentUrl = new URL(window.location.href);
            const fragmentUrl = new URL('/ShowRosterWeekStaffPanelFragment', window.location.origin);
            const revisionInput = actionForm.elements.namedItem('rosterCalendarRevision');
            if (!(revisionInput instanceof HTMLInputElement)) throw new Error('Expected roster calendar revision input');
            fragmentUrl.searchParams.set('anchorDate', currentUrl.searchParams.get('anchorDate') ?? '');
            fragmentUrl.searchParams.set('rosterGroupId', actionUrl.searchParams.get('rosterGroupId') ?? '');
            fragmentUrl.searchParams.set('rosterCalendarRevision', revisionInput.value);
            const htmx = (window as Window & {
                htmx?: { ajax: (method: string, url: string, options: { target: string; swap: string }) => unknown };
            }).htmx;
            if (!htmx) throw new Error('Expected htmx runtime');
            htmx.ajax('GET', fragmentUrl.toString(), { target: '#roster-staff-panel-fragment', swap: 'outerHTML' });
        });
        await fragmentResponse;
        await fragmentSettled;
        await expect.poll(() => originalStaffPanel.evaluate((panel) => panel.isConnected), { timeout: E2E_TIMEOUT.assertion }).toBe(false);
        await expect(page.getByRole('tab', { name: 'Settings', exact: true })).toHaveAttribute('aria-selected', 'true');
        await expect(page.locator('#roster-staff-panel-settings-pane')).toBeVisible();
        expect(tabSetBoundaryErrors).toEqual([]);
    });

    test('labels the single time column as start in day-row mode', async ({ page }) => {
        await loginAndOpenRoster(page);
        const frame = page.locator('.roster-grid-frame[data-roster-layout="day_rows"]');
        await expect(frame).toBeVisible();

        const subheaders = page.locator('.roster-slots-scroller .roster-grid-header-row-subheads .roster-subhead');
        await expect(subheaders.first()).toHaveText('Start');
        if ((await frame.getAttribute('data-roster-end-times')) === 'true') {
            await expect(subheaders.nth(1)).toHaveText('End');
        } else {
            await expect(subheaders.filter({ hasText: /^Time$/ })).toHaveCount(0);
        }
    });

    test('reveals a centred green create affordance only on hover', async ({ page }) => {
        await loginAndOpenRoster(page);

        const createUnit = page.locator('.roster-grid-frame[data-roster-layout="day_rows"] .roster-shift-create-unit').first();
        const createAffordance = createUnit.locator('.roster-shift-create-plus-overlay');

        await expect(createUnit).toBeVisible();
        await expect(createAffordance).toBeAttached();
        await expect(createAffordance).toHaveCSS('position', 'absolute');
        await expect(createAffordance).toHaveCSS('opacity', '0');

        await createUnit.hover();
        await expect(createAffordance).toHaveCSS('opacity', '1');

        const metrics = await createUnit.evaluate((unit) => {
            const affordance = unit.querySelector('.roster-shift-create-plus-overlay');
            if (!(unit instanceof HTMLElement) || !(affordance instanceof HTMLElement)) return null;

            const successProbe = document.createElement('span');
            successProbe.style.color = 'var(--bs-success)';
            document.body.appendChild(successProbe);

            const unitRect = unit.getBoundingClientRect();
            const affordanceRect = affordance.getBoundingClientRect();
            const result = {
                unitCenterX: unitRect.left + unitRect.width / 2,
                unitCenterY: unitRect.top + unitRect.height / 2,
                affordanceCenterX: affordanceRect.left + affordanceRect.width / 2,
                affordanceCenterY: affordanceRect.top + affordanceRect.height / 2,
                affordanceColor: getComputedStyle(affordance).color,
                successColor: getComputedStyle(successProbe).color,
            };

            successProbe.remove();
            return result;
        });

        expect(metrics).not.toBeNull();
        expect(metrics?.affordanceColor).toBe(metrics?.successColor);
        expect(metrics?.affordanceCenterX).toBeCloseTo(metrics?.unitCenterX ?? 0, 0);
        expect(metrics?.affordanceCenterY).toBeCloseTo(metrics?.unitCenterY ?? 0, 0);
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

        await expect(await rosterDayAddButtonForSection(daySection)).toBeAttached();
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
        expect(sidebarMetrics?.sideTop ?? 0).toBeGreaterThanOrEqual(sidebarMetrics?.sideStickyTop ?? 0);
        expect(sidebarMetrics?.panelHeight ?? 0).toBeLessThanOrEqual(sidebarMetrics?.viewportHeight ?? 0);
        expect(sidebarMetrics?.panelOverflow).toBe('hidden');
        expect(sidebarMetrics?.listOverflow).toBe('auto');
        expect(sidebarMetrics?.listScrollHeight ?? 0).toBeGreaterThan(sidebarMetrics?.listClientHeight ?? 0);
        expect(sidebarMetrics?.listScrollTop ?? 0).toBeGreaterThan(0);
    });

    test('clips day-column cards and keeps compact controls aligned', async ({ page }) => {
        await loginAndOpenRoster(page);
        await page.setViewportSize({ width: 1280, height: 900 });
        if ((await existingRosterShiftLaunchers(page).count()) === 0) {
            await assignRosterShiftStaff(page, rosterShiftLaunchers(page).first(), 'a1000000-0000-0000-0000-000000000031');
        }

        await openRosterSettings(page);
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
            };

            conflictProbe.remove();
            return metrics;
        });

        expect(metrics).not.toBeNull();
        expect(metrics?.columnOverflow).toBe('hidden');
        expect(metrics?.columnRadius).not.toBe('0px');
        expect(metrics?.createDisplay).toBe('flex');
        expect(metrics?.createHasEmptyClass).toBe(true);
        expect(metrics?.fieldsOverflow).toBe('hidden');
        expect(metrics?.fieldsRadius).not.toBe('0px');
        expect(metrics?.timeBackground).toBe(metrics?.codeBackground);
        expect(metrics?.timeBackground).not.toBe(metrics?.conflictBackground);
        expect(metrics?.badgeDisplay).toBe('flex');
        expect(metrics?.staffBackground).not.toBe(metrics?.conflictBackground);
        expect(metrics?.timeFontSize).toBe(metrics?.staffFontSize);
        expect(metrics?.timeFontSize).toBe(metrics?.shiftTypeFontSize);
        expect(metrics?.cardHasConflictClass).toBe(false);
        expect(metrics?.timeStaticBorderWidth).toBe('0px');
        expect(metrics?.staffStaticBorderWidth).toBe('0px');
    });

    test('centres read-only day-column names and keeps times on one line', async ({ page }) => {
        await page.setViewportSize({ width: 1280, height: 900 });
        await loginAndOpenRoster(page);

        await openRosterSettings(page);
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
