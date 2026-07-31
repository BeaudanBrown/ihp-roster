import { test, expect, Page } from '@playwright/test';
import {
    dialogMountDomAttr,
    dialogOverlayMountDomId,
    orderedRangeAvailabilityDomAttr,
    orderedRangeConfigDomAttr,
    orderedRangeEndDomAttr,
    orderedRangeEndPositionProperty,
    orderedRangeRootDomAttr,
    orderedRangeStartDomAttr,
    orderedRangeStartPositionProperty,
    orderedRangeStateDomAttr,
    pageReadyEvent,
    parseOrderedRangeConfig,
    parseOrderedRangeState,
} from '../frontend/ts/generated/contracts';
import { gotoWhenReady, loginAs, openRoster } from './test-helpers';
import { E2E_TIMEOUT } from './timeouts';

async function expectLocalStylesheet(page: Page, path: string) {
    const link = page.locator(`link[rel="stylesheet"][href*="${path}"]`);
    await expect(link).toHaveCount(1);
    await expectStylesheetServed(page, path);
}

async function expectStylesheetServed(page: Page, path: string) {
    const response = await page.request.get(path);
    expect(response.ok()).toBeTruthy();
    expect(response.headers()['content-type']).toContain('text/css');
}

const sharedComponentStylesheets = [
    '/css/components/surfaces.css',
    '/css/components/menus.css',
    '/css/components/horizontal.css',
    '/css/components/week-nav.css',
    '/css/components/status.css',
    '/css/components/public.css',
    '/css/components/panels.css',
    '/css/components/forms.css',
    '/css/components/buttons.css',
    '/css/components/bootstrap-overrides.css',
    '/css/components/accordions.css',
    '/css/components/admin.css',
    '/css/components/week-toolbar.css',
    '/css/components/admin-responsive.css',
];

test.describe('Styling regression contracts', () => {
    test.use({ viewport: { width: 1280, height: 900 } });

    test('loads the split roster styles and applies the desktop roster grid contract', async ({ page }) => {
        await openRoster(page, { ensureEditable: false });

        await expectLocalStylesheet(page, '/css/tokens.css');
        await expectLocalStylesheet(page, '/css/palette.css');
        await expectLocalStylesheet(page, '/css/bootstrap-bridge.css');
        for (const stylesheet of sharedComponentStylesheets) {
            await expectLocalStylesheet(page, stylesheet);
        }
        const rosterStylesheets = [
            '/css/features/roster/toolbar.css',
            '/css/features/roster/week-overview.css',
            '/css/features/roster/staff-panel.css',
            '/css/features/roster/grid-frame.css',
            '/css/features/roster/day-actions.css',
            '/css/features/roster/staff-highlight.css',
            '/css/features/roster/grid-cells.css',
            '/css/features/roster/day-columns.css',
            '/css/features/roster/shift-card.css',
            '/css/features/roster/responsive.css',
            '/css/features/roster/grid-controls.css',
            '/css/features/roster/states.css',
            '/css/features/roster/export-print.css',
        ];
        for (const stylesheet of rosterStylesheets) {
            await expectLocalStylesheet(page, stylesheet);
        }

        const metrics = await page.locator('.roster-grid-frame').first().evaluate((frame) => {
            if (!(frame instanceof HTMLElement)) {
                throw new Error('Expected roster grid frame to be an HTMLElement');
            }

            const scroller = frame.querySelector('.roster-slots-scroller');
            const grid = frame.querySelector('.roster-grid');
            const gridHeader = document.querySelector('.roster-grid-header');
            const navGroup = document.querySelector('.roster-week-nav-group');
            const renderedDayCell = document.querySelector('.roster-grid .day-row[class*="day-alt-"] [role="gridcell"]');
            const renderedDayRail = document.querySelector('.roster-day-rail-section[class*="day-alt-"]');

            if (
                !(scroller instanceof HTMLElement)
                || !(grid instanceof HTMLElement)
                || !(gridHeader instanceof HTMLElement)
                || !(navGroup instanceof HTMLElement)
                || !(renderedDayCell instanceof HTMLElement)
                || !(renderedDayRail instanceof HTMLElement)
            ) {
                return null;
            }

            const probe = document.createElement('div');
            probe.className = 'roster-grid';
            probe.style.position = 'absolute';
            probe.style.left = '-10000px';
            probe.innerHTML = `
                <div class="day-row day-alt-light"><div role="gridcell">light</div><div role="gridcell" class="slot-empty-cell">empty</div></div>
                <div class="day-row day-alt-dark"><div role="gridcell">dark</div><div role="gridcell" class="slot-empty-cell">empty</div></div>
                <div class="roster-grid-day-section" style="--roster-day-row-count:2;">
                    <div class="day-row day-alt-light"><div role="gridcell" class="probe-first-section-first-cell">first day first row</div></div>
                    <div class="day-row day-alt-light"><div role="gridcell" class="probe-first-section-second-cell">first day second row</div></div>
                </div>
                <div class="roster-grid-day-section" style="--roster-day-row-count:1;">
                    <div class="day-row day-alt-dark"><div role="gridcell" class="probe-second-section-first-cell">second day first row</div></div>
                </div>`;
            document.body.appendChild(probe);

            const probeLightCell = probe.querySelector('.day-alt-light');
            const probeDarkCell = probe.querySelector('.day-alt-dark');
            const probeLightEmptyCell = probe.querySelector('.day-alt-light .slot-empty-cell');
            const probeDarkEmptyCell = probe.querySelector('.day-alt-dark .slot-empty-cell');
            const probeFirstSectionFirstCell = probe.querySelector('.probe-first-section-first-cell');
            const probeFirstSectionSecondCell = probe.querySelector('.probe-first-section-second-cell');
            const probeSecondSectionFirstCell = probe.querySelector('.probe-second-section-first-cell');

            const cornerProbe = document.createElement('div');
            cornerProbe.className = 'roster-grid-frame';
            cornerProbe.style.position = 'absolute';
            cornerProbe.style.left = '-10000px';
            cornerProbe.innerHTML = `
                <div class="roster-grid">
                    <div class="roster-grid-day-section" style="--roster-day-row-count:1;">
                        <div class="day-row day-alt-light">
                            <div role="gridcell" class="slot-time-cell" data-roster-shift-colour="palette-1">time</div>
                            <div role="gridcell" class="slot-staff-cell" data-roster-shift-colour="palette-1">staff</div>
                            <div role="gridcell" class="slot-shift-type-cell roster-block-end probe-non-final-block-end" data-roster-shift-colour="palette-1">code</div>
                            <div role="gridcell" class="slot-time-cell roster-block-start" data-roster-shift-colour="palette-2">time</div>
                            <div role="gridcell" class="slot-staff-cell" data-roster-shift-colour="palette-2">staff</div>
                            <div role="gridcell" class="slot-shift-type-cell roster-block-end probe-final-block-end" data-roster-shift-colour="palette-2">code</div>
                        </div>
                    </div>
                </div>`;
            document.body.appendChild(cornerProbe);

            const probeNonFinalBlockEnd = cornerProbe.querySelector('.probe-non-final-block-end');
            const probeFinalBlockEnd = cornerProbe.querySelector('.probe-final-block-end');

            if (
                !(probeLightCell instanceof HTMLElement)
                || !(probeDarkCell instanceof HTMLElement)
                || !(probeLightEmptyCell instanceof HTMLElement)
                || !(probeDarkEmptyCell instanceof HTMLElement)
                || !(probeFirstSectionFirstCell instanceof HTMLElement)
                || !(probeFirstSectionSecondCell instanceof HTMLElement)
                || !(probeSecondSectionFirstCell instanceof HTMLElement)
                || !(probeNonFinalBlockEnd instanceof HTMLElement)
                || !(probeFinalBlockEnd instanceof HTMLElement)
            ) {
                probe.remove();
                cornerProbe.remove();
                return null;
            }

            const renderedDayCellStyle = getComputedStyle(renderedDayCell);
            const renderedDayRailStyle = getComputedStyle(renderedDayRail);
            const probeLightStyle = getComputedStyle(probeLightCell);
            const probeDarkStyle = getComputedStyle(probeDarkCell);
            const probeLightEmptyStyle = getComputedStyle(probeLightEmptyCell);
            const probeDarkEmptyStyle = getComputedStyle(probeDarkEmptyCell);
            const probeFirstSectionFirstCellStyle = getComputedStyle(probeFirstSectionFirstCell);
            const probeFirstSectionSecondCellStyle = getComputedStyle(probeFirstSectionSecondCell);
            const probeSecondSectionFirstCellStyle = getComputedStyle(probeSecondSectionFirstCell);
            const probeNonFinalBlockEndPseudoStyle = getComputedStyle(probeNonFinalBlockEnd, '::before');
            const probeFinalBlockEndPseudoStyle = getComputedStyle(probeFinalBlockEnd, '::before');

            const probeMetrics = {
                lightDayCellBackground: probeLightStyle.backgroundColor,
                darkDayCellBackground: probeDarkStyle.backgroundColor,
                lightEmptyCellBackground: probeLightEmptyStyle.backgroundColor,
                darkEmptyCellBackground: probeDarkEmptyStyle.backgroundColor,
                firstDayFirstRowBorderTop: probeFirstSectionFirstCellStyle.borderTopColor,
                firstDaySecondRowBorderTop: probeFirstSectionSecondCellStyle.borderTopColor,
                secondDayFirstRowBorderTop: probeSecondSectionFirstCellStyle.borderTopColor,
                nonFinalBlockEndBottomRightRadius: probeNonFinalBlockEndPseudoStyle.borderBottomRightRadius,
                finalBlockEndBottomRightRadius: probeFinalBlockEndPseudoStyle.borderBottomRightRadius,
            };
            probe.remove();
            cornerProbe.remove();

            const railSections = Array.from(frame.querySelectorAll('.roster-day-rail-section'));
            const gridSections = Array.from(frame.querySelectorAll('.roster-grid-day-section'));
            const sectionDeltas = railSections.map((railSection, index) => {
                const gridSection = gridSections[index];
                if (!(railSection instanceof HTMLElement) || !(gridSection instanceof HTMLElement)) {
                    return 999;
                }
                const railRect = railSection.getBoundingClientRect();
                const gridRect = gridSection.getBoundingClientRect();
                return Math.max(Math.abs(railRect.top - gridRect.top), Math.abs(railRect.bottom - gridRect.bottom));
            });

            return {
                tableOverflowX: getComputedStyle(scroller).overflowX,
                tableScrollWidth: scroller.scrollWidth,
                tableClientWidth: scroller.clientWidth,
                frameScrollWidth: frame.scrollWidth,
                frameClientWidth: frame.clientWidth,
                tableMinWidth: getComputedStyle(grid).minWidth,
                headerPosition: getComputedStyle(gridHeader).position,
                headerDisplay: getComputedStyle(gridHeader).display,
                navBorderRadius: getComputedStyle(navGroup).borderRadius,
                navBackground: getComputedStyle(navGroup).backgroundColor,
                navItemMargins: Array.from(navGroup.children).map((child) => getComputedStyle(child).marginLeft),
                navButtonBorders: Array.from(navGroup.querySelectorAll('.roster-week-nav-button')).map((child) => getComputedStyle(child).borderColor),
                navWeekLabelRadius: getComputedStyle(navGroup.querySelector('.roster-week-nav-label') as Element).borderRadius,
                renderedDayCellBackground: renderedDayCellStyle.backgroundColor,
                renderedDayRailBackground: renderedDayRailStyle.backgroundColor,
                sectionDeltas,
                ...probeMetrics,
            };
        });

        expect(metrics).not.toBeNull();
        expect(metrics?.tableOverflowX).toBe('auto');
        expect(metrics?.tableScrollWidth).toBeGreaterThanOrEqual(metrics?.tableClientWidth ?? 0);
        expect(metrics?.frameScrollWidth).toBeLessThanOrEqual((metrics?.frameClientWidth ?? 0) + 1);
        expect(metrics?.tableMinWidth).not.toBe('0px');
        expect(metrics?.headerPosition).toBe('relative');
        expect(metrics?.headerDisplay).toBe('grid');
        expect(Number.parseFloat(metrics?.navBorderRadius ?? '0')).toBeGreaterThan(100);
        expect(metrics?.navBackground).not.toBe('rgba(0, 0, 0, 0)');
        expect(metrics?.navItemMargins.every((margin) => margin === '0px')).toBe(true);
        expect(metrics?.navButtonBorders.every((border) => border === 'rgba(0, 0, 0, 0)')).toBe(true);
        expect(Number.parseFloat(metrics?.navWeekLabelRadius ?? '0')).toBeGreaterThan(100);
        expect(metrics?.renderedDayCellBackground).not.toBe('rgb(13, 17, 25)');
        expect(metrics?.renderedDayRailBackground).not.toBe('rgb(13, 17, 25)');
        expect(metrics?.lightDayCellBackground).not.toBe(metrics?.darkDayCellBackground);
        expect(metrics?.lightDayCellBackground).not.toBe('rgb(13, 17, 25)');
        expect(metrics?.lightEmptyCellBackground).toBe(metrics?.lightDayCellBackground);
        expect(metrics?.darkEmptyCellBackground).toBe(metrics?.darkDayCellBackground);
        expect(metrics?.firstDaySecondRowBorderTop).not.toBe(metrics?.firstDayFirstRowBorderTop);
        expect(metrics?.secondDayFirstRowBorderTop).toBe(metrics?.firstDaySecondRowBorderTop);
        expect(metrics?.nonFinalBlockEndBottomRightRadius).toBe('0px');
        expect(Number.parseFloat(metrics?.finalBlockEndBottomRightRadius ?? '0')).toBeGreaterThan(0);
        expect(metrics?.sectionDeltas.every((delta) => delta <= 1)).toBe(true);
    });

    test('keeps shared accordion panel styling applied on the profile page', async ({ page }) => {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await gotoWhenReady(page, '/EditProfile?section=profile', '#profile-sections');

        for (const stylesheet of sharedComponentStylesheets) {
            await expectLocalStylesheet(page, stylesheet);
        }

        const metrics = await page.locator('#profile-sections').evaluate((sections) => {
            if (!(sections instanceof HTMLElement)) {
                throw new Error('Expected profile sections to be an HTMLElement');
            }

            const openItem = sections.querySelector('.accordion-item.app-panel:has(.accordion-button:not(.collapsed))');
            const collapsedItem = sections.querySelector('.accordion-item.app-panel:has(.accordion-button.collapsed)');

            if (!(openItem instanceof HTMLElement) || !(collapsedItem instanceof HTMLElement)) {
                return null;
            }

            const openButton = openItem.querySelector('.accordion-button:not(.collapsed)');
            const collapsedButton = collapsedItem.querySelector('.accordion-button.collapsed');
            const body = openItem.querySelector('.accordion-body');

            if (!(openButton instanceof HTMLElement) || !(collapsedButton instanceof HTMLElement) || !(body instanceof HTMLElement)) {
                return null;
            }

            return {
                openItemBackground: getComputedStyle(openItem).backgroundColor,
                openItemBorderColor: getComputedStyle(openItem).borderColor,
                openButtonBackground: getComputedStyle(openButton).backgroundColor,
                openButtonColor: getComputedStyle(openButton).color,
                openButtonBorderBottomColor: getComputedStyle(openButton).borderBottomColor,
                openButtonBorderBottomLeftRadius: getComputedStyle(openButton).borderBottomLeftRadius,
                openButtonBorderBottomRightRadius: getComputedStyle(openButton).borderBottomRightRadius,
                openButtonBoxShadow: getComputedStyle(openButton).boxShadow,
                collapsedButtonBackground: getComputedStyle(collapsedButton).backgroundColor,
                collapsedButtonColor: getComputedStyle(collapsedButton).color,
                openCollapseBorderRadius: getComputedStyle(openItem.querySelector('.accordion-collapse') as Element).borderRadius,
                bodyBorderTop: getComputedStyle(body).borderTopWidth,
                bodyBorderRadius: getComputedStyle(body).borderRadius,
                bodyBackground: getComputedStyle(body).backgroundColor,
            };
        });

        expect(metrics).not.toBeNull();
        expect(metrics?.openItemBorderColor).not.toBe('rgb(0, 0, 0)');
        expect(metrics?.openButtonBorderBottomLeftRadius).toBe('0px');
        expect(metrics?.openButtonBorderBottomRightRadius).toBe('0px');
        expect(metrics?.openCollapseBorderRadius).toBe('0px 0px 13.4px 13.4px');
        expect(metrics?.bodyBorderTop).toBe('1px');
        expect(metrics?.bodyBorderRadius).toBe('0px 0px 13.4px 13.4px');

        const openItem = page.locator('#profile-sections .accordion-item.app-panel:has(.accordion-button:not(.collapsed))').first();
        const collapsedItem = page.locator('#profile-sections .accordion-item.app-panel:has(.accordion-button.collapsed)').first();
        const openTopBeforeHover = await openItem.evaluate((item) => item.getBoundingClientRect().top);
        await openItem.hover();
        await expect.poll(async () => openItem.evaluate((item) => getComputedStyle(item).transform)).toBe('none');
        expect(await openItem.evaluate((item) => item.getBoundingClientRect().top)).toBeCloseTo(openTopBeforeHover, 1);

        await collapsedItem.hover();
        await expect.poll(async () => collapsedItem.evaluate((item) => getComputedStyle(item).transform)).not.toBe('none');
    });

    test('preserves profile ordered-range crossing, availability, labels, and HTMX values', async ({ page }) => {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await gotoWhenReady(page, '/EditProfile?section=profile', '#profile-content-fragment');
        const profileDetailsToggle = page.getByRole('button', { name: 'Profile Details', exact: true });
        if ((await profileDetailsToggle.getAttribute('aria-expanded')) !== 'true') {
            await profileDetailsToggle.click();
        }

        const shiftPreferencesToggle = page.getByRole('button', { name: 'Shift Preferences', exact: true });
        if ((await shiftPreferencesToggle.getAttribute('aria-expanded')) !== 'true') {
            await shiftPreferencesToggle.click();
        }

        const rangeRoots = page.locator(`[${orderedRangeRootDomAttr}]`);
        const firstRange = rangeRoots.first();
        await expect(firstRange).toBeVisible();

        const rawConfig = await firstRange.getAttribute(orderedRangeConfigDomAttr);
        const rawState = await firstRange.getAttribute(orderedRangeStateDomAttr);
        if (rawConfig === null || rawState === null) throw new Error('Expected generated ordered-range payloads');
        const config = parseOrderedRangeConfig(JSON.parse(rawConfig));
        parseOrderedRangeState(JSON.parse(rawState));

        const diagnostics: string[] = [];
        page.on('console', (message) => {
            if (message.type() === 'error') diagnostics.push(message.text());
        });
        const malformedResult = await firstRange.evaluate((root, contract) => {
            if (!(root instanceof HTMLElement) || root.parentElement === null) {
                throw new Error('Expected mounted ordered-range root');
            }
            const clone = root.cloneNode(true);
            if (!(clone instanceof HTMLElement)) throw new Error('Expected cloned ordered-range root');
            const cloneConfig = clone.getAttribute(contract.configAttr);
            if (cloneConfig === null) throw new Error('Expected cloned ordered-range config');
            clone.setAttribute(contract.configAttr, JSON.stringify({ ...JSON.parse(cloneConfig), extra: true }));
            root.parentElement.append(clone);
            const beforeInitialization = clone.outerHTML;
            document.dispatchEvent(new CustomEvent(contract.readyEvent, { detail: { target: clone } }));
            const afterInitialization = clone.outerHTML;
            clone.remove();
            return { beforeInitialization, afterInitialization };
        }, { configAttr: orderedRangeConfigDomAttr, readyEvent: pageReadyEvent });
        expect(malformedResult.afterInitialization).toBe(malformedResult.beforeInitialization);
        await expect.poll(
            () => diagnostics.some((message) => message.includes('Invalid generated ordered-range configuration')),
            { timeout: E2E_TIMEOUT.assertion },
        ).toBe(true);

        const startInput = firstRange.locator(`[${orderedRangeStartDomAttr}]`);
        const endInput = firstRange.locator(`[${orderedRangeEndDomAttr}]`);
        const availabilityInput = firstRange.locator(`[${orderedRangeAvailabilityDomAttr}] input[type="checkbox"]`);
        await expect(startInput).toHaveAccessibleName('Earliest preferred start');
        await expect(endInput).toHaveAccessibleName('Latest preferred start');

        if (!(await availabilityInput.isChecked())) {
            await firstRange.locator(`[${orderedRangeAvailabilityDomAttr}] label`).click();
        }
        await expect(startInput).toBeEnabled();
        await expect(endInput).toBeEnabled();

        const dispatchRangeInput = async (input: ReturnType<typeof firstRange.locator>, value: number) => {
            await input.evaluate((element, nextValue) => {
                if (!(element instanceof HTMLInputElement)) throw new Error('Expected native range input');
                element.value = String(nextValue);
                element.dispatchEvent(new Event('input', { bubbles: true }));
            }, value);
        };

        await dispatchRangeInput(endInput, config.minimumValue);
        await dispatchRangeInput(startInput, config.maximumValue);
        await expect(startInput).toHaveValue(String(config.maximumValue));
        await expect(endInput).toHaveValue(String(config.maximumValue));

        await dispatchRangeInput(endInput, config.minimumValue);
        await expect(startInput).toHaveValue(String(config.minimumValue));
        await expect(endInput).toHaveValue(String(config.minimumValue));

        await dispatchRangeInput(endInput, config.defaultEndValue);
        await dispatchRangeInput(startInput, config.defaultStartValue);
        await expect(startInput).toHaveValue(String(config.defaultStartValue));
        await expect(endInput).toHaveValue(String(config.defaultEndValue));

        const startId = await startInput.getAttribute('id');
        const endId = await endInput.getAttribute('id');
        const startName = await startInput.getAttribute('name');
        const endName = await endInput.getAttribute('name');
        if (startId === null || endId === null || startName === null || endName === null) {
            throw new Error('Expected named and labelled ordered-range endpoints');
        }
        const startLabelIndex = (config.defaultStartValue - config.minimumValue) / config.stepValue;
        const endLabelIndex = (config.defaultEndValue - config.minimumValue) / config.stepValue;
        await expect(firstRange.locator(`output[for="${startId}"]`)).toHaveText(config.valueLabels[startLabelIndex]);
        await expect(firstRange.locator(`output[for="${endId}"]`)).toHaveText(config.valueLabels[endLabelIndex]);

        await firstRange.locator(`[${orderedRangeAvailabilityDomAttr}] label`).click();
        await expect(startInput).toBeDisabled();
        await expect(endInput).toBeDisabled();
        await firstRange.locator(`[${orderedRangeAvailabilityDomAttr}] label`).click();
        await expect(startInput).toBeEnabled();
        await expect(endInput).toBeEnabled();

        await page.evaluate(() => window.scrollTo(0, 240));
        const beforeScrollY = await page.evaluate(() => window.scrollY);
        const saveButton = page.locator('#profile-shift-preferences-form button[type="submit"]');
        const [request] = await Promise.all([
            page.waitForRequest((candidate) => candidate.url().includes('/UpdateProfile') && candidate.method() === 'POST'),
            page.waitForResponse((response) => response.url().includes('/UpdateProfile') && response.request().method() === 'POST'),
            saveButton.click(),
        ]);
        const submitted = new URLSearchParams(request.postData() ?? '');
        expect(submitted.get(startName)).toBe(String(config.defaultStartValue));
        expect(submitted.get(endName)).toBe(String(config.defaultEndValue));
        await expect(page.locator('#profile-content-fragment')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });

        const refreshedStart = page.locator(`[${orderedRangeStartDomAttr}][name="${startName}"]`);
        const refreshedEnd = page.locator(`[${orderedRangeEndDomAttr}][name="${endName}"]`);
        await expect(refreshedStart).toHaveValue(String(config.defaultStartValue));
        await expect(refreshedEnd).toHaveValue(String(config.defaultEndValue));

        for (let index = 0; index < await rangeRoots.count(); index += 1) {
            const root = rangeRoots.nth(index);
            const endpoint = root.locator(`[${orderedRangeStartDomAttr}]`);
            const endpointId = await endpoint.getAttribute('id');
            const endpointValue = Number(await endpoint.inputValue());
            const configJson = await root.getAttribute(orderedRangeConfigDomAttr);
            if (endpointId === null || configJson === null) throw new Error('Expected complete ordered-range row');
            const rowConfig = parseOrderedRangeConfig(JSON.parse(configJson));
            const labelIndex = (endpointValue - rowConfig.minimumValue) / rowConfig.stepValue;
            await expect(root.locator(`output[for="${endpointId}"]`)).toHaveText(rowConfig.valueLabels[labelIndex]);
            const startCss = await root.evaluate((element, property) => {
                if (!(element instanceof HTMLElement)) throw new Error('Expected ordered-range root');
                return element.style.getPropertyValue(property);
            }, orderedRangeStartPositionProperty);
            const endCss = await root.evaluate((element, property) => {
                if (!(element instanceof HTMLElement)) throw new Error('Expected ordered-range root');
                return element.style.getPropertyValue(property);
            }, orderedRangeEndPositionProperty);
            expect(startCss).not.toBe('');
            expect(endCss).not.toBe('');
        }

        const scrollY = await page.evaluate(() => window.scrollY);
        expect(scrollY).toBeGreaterThan(Math.max(0, beforeScrollY - 120));
    });

    test('flattens nested app panels inside accordion bodies', async ({ page }) => {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await gotoWhenReady(page, '/EditProfile?section=profile', '#profile-sections');

        const metrics = await page.evaluate(() => {
            const probe = document.createElement('div');
            probe.className = 'accordion-item app-panel';
            probe.style.position = 'absolute';
            probe.style.left = '-10000px';
            probe.innerHTML = `
                <h2 class="accordion-header">
                    <button class="accordion-button" type="button">Probe</button>
                </h2>
                <div class="accordion-collapse collapse show">
                    <div class="accordion-body p-0">
                        <section class="app-panel">
                            <div class="app-panel-header">Nested panel header</div>
                            <div class="app-panel-body">Nested panel body</div>
                        </section>
                    </div>
                </div>`;
            document.body.appendChild(probe);

            const panel = probe.querySelector('.accordion-body.p-0 > .app-panel');
            const header = probe.querySelector('.accordion-body.p-0 > .app-panel > .app-panel-header');

            if (!(panel instanceof HTMLElement) || !(header instanceof HTMLElement)) {
                probe.remove();
                return null;
            }

            const panelStyle = getComputedStyle(panel);
            const headerStyle = getComputedStyle(header);
            const result = {
                borderTopWidth: panelStyle.borderTopWidth,
                borderRadius: panelStyle.borderRadius,
                boxShadow: panelStyle.boxShadow,
                background: panelStyle.backgroundColor,
                headerBorderTopWidth: headerStyle.borderTopWidth,
            };
            probe.remove();
            return result;
        });

        expect(metrics).not.toBeNull();
        expect(metrics?.borderTopWidth).toBe('0px');
        expect(metrics?.borderRadius).toBe('0px');
        expect(metrics?.boxShadow).toBe('none');
        expect(metrics?.background).toBe('rgba(0, 0, 0, 0)');
        expect(metrics?.headerBorderTopWidth).toBe('0px');
    });

    test('uses the shared accordion contract on the leave page', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/LeaveRequests', '#leave-requests-content');

        const leaveMetrics = await page.locator('#leave-request-manager-sections').evaluate((accordion) => {
            if (!(accordion instanceof HTMLElement)) {
                throw new Error('Expected leave accordion to be an HTMLElement');
            }

            return Array.from(accordion.querySelectorAll('.accordion-item.app-panel')).map((item) => {
                const button = item.querySelector('.accordion-button');
                const body = item.querySelector('.accordion-body');

                return {
                    tagName: item.tagName,
                    buttonBackground: button instanceof HTMLElement ? getComputedStyle(button).backgroundColor : '',
                    buttonBottomLeftRadius: button instanceof HTMLElement ? getComputedStyle(button).borderBottomLeftRadius : '',
                    buttonBottomRightRadius: button instanceof HTMLElement ? getComputedStyle(button).borderBottomRightRadius : '',
                    bodyRadius: body instanceof HTMLElement ? getComputedStyle(body).borderRadius : '',
                };
            });
        });

        expect(leaveMetrics).toHaveLength(4);
        expect(leaveMetrics.every((metric) => metric.tagName === 'SECTION')).toBe(true);
        expect(leaveMetrics.every((metric) => metric.bodyRadius === '0px 0px 13.4px 13.4px')).toBe(true);
        expect(leaveMetrics[0].buttonBackground).toBeTruthy();
        expect(leaveMetrics[0].buttonBottomLeftRadius).toBe('0px');
        expect(leaveMetrics[0].buttonBottomRightRadius).toBe('0px');
    });

    test('keeps workflow dialogs on app modal and action tokens', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/LeaveRequests', '#leave-requests-content');

        await expectStylesheetServed(page, '/css/bootstrap-bridge.css');
        await expectStylesheetServed(page, '/css/overlays.css');

        await page.getByRole('button', { name: 'feedback', exact: true }).click();
        await expect(page.locator(`#${dialogOverlayMountDomId} [${dialogMountDomAttr}]`)).toBeVisible();

        const modalMetrics = await page.locator(`#${dialogOverlayMountDomId} [${dialogMountDomAttr}]`).evaluate((dialog) => {
            if (!(dialog instanceof HTMLElement)) {
                throw new Error('Expected workflow dialog overlay to be an HTMLElement');
            }

            const content = dialog.querySelector('.modal-content');
            const header = dialog.querySelector('.modal-header');
            const footer = dialog.querySelector('.modal-footer');
            const primaryButton = dialog.querySelector('.btn-primary');

            if (
                !(content instanceof HTMLElement)
                || !(header instanceof HTMLElement)
                || !(footer instanceof HTMLElement)
                || !(primaryButton instanceof HTMLElement)
            ) {
                return null;
            }

            const rootStyle = getComputedStyle(document.documentElement);
            const contentStyle = getComputedStyle(content);
            const headerStyle = getComputedStyle(header);
            const footerStyle = getComputedStyle(footer);
            const primaryStyle = getComputedStyle(primaryButton);

            return {
                appBackground: rootStyle.getPropertyValue('--app-bg').trim(),
                appSurface2: rootStyle.getPropertyValue('--app-surface-2').trim(),
                appModalBackground: rootStyle.getPropertyValue('--app-modal-bg').trim(),
                appAccent: rootStyle.getPropertyValue('--app-accent').trim(),
                contentBackgroundColor: contentStyle.backgroundColor,
                contentBackgroundImage: contentStyle.backgroundImage,
                contentBorderColor: contentStyle.borderColor,
                contentBoxShadow: contentStyle.boxShadow,
                headerBackgroundColor: headerStyle.backgroundColor,
                headerBorderBottomColor: headerStyle.borderBottomColor,
                footerBackgroundColor: footerStyle.backgroundColor,
                footerBorderTopColor: footerStyle.borderTopColor,
                primaryButtonBackground: primaryStyle.backgroundColor,
                primaryButtonBorderColor: primaryStyle.borderColor,
                primaryButtonColor: primaryStyle.color,
            };
        });

        expect(modalMetrics).not.toBeNull();
        expect(modalMetrics?.contentBackgroundColor).not.toBe('rgb(13, 17, 25)');
        expect(modalMetrics?.contentBackgroundImage).toContain('linear-gradient');
        expect(modalMetrics?.contentBorderColor).not.toBe('rgba(255, 255, 255, 0.15)');
        expect(modalMetrics?.contentBoxShadow).not.toBe('rgba(0, 0, 0, 0.15) 0px 8px 16px 0px');
        expect(modalMetrics?.headerBackgroundColor).toBe('rgb(26, 34, 48)');
        expect(modalMetrics?.footerBackgroundColor).toBe('rgb(20, 26, 36)');
        expect(modalMetrics?.headerBorderBottomColor).toBe('rgb(42, 52, 70)');
        expect(modalMetrics?.footerBorderTopColor).toBe('rgb(42, 52, 70)');
        expect(modalMetrics?.primaryButtonBackground).toBe('rgb(139, 181, 255)');
        expect(modalMetrics?.primaryButtonBorderColor).toBe('rgb(139, 181, 255)');
        expect(modalMetrics?.primaryButtonBackground).not.toBe('rgb(13, 110, 253)');
        expect(modalMetrics?.primaryButtonColor).toBe('rgb(13, 17, 25)');
    });

    test('applies roster responsive styles on phone-sized viewports', async ({ page }) => {
        await page.setViewportSize({ width: 390, height: 844 });
        await openRoster(page, { email: 'e2e-test@example.com', ensureEditable: true });

        const metrics = await page.locator('.roster-grid-header').evaluate((header) => {
            if (!(header instanceof HTMLElement)) {
                throw new Error('Expected roster grid header to be an HTMLElement');
            }

            const navigation = header.querySelector('.app-week-toolbar-navigation');
            const primary = header.querySelector('.app-week-toolbar-primary');
            const tableContainer = document.querySelector('.roster-slots-scroller');
            const grid = document.querySelector('.roster-grid');

            if (!(navigation instanceof HTMLElement) || !(primary instanceof HTMLElement) || !(tableContainer instanceof HTMLElement) || !(grid instanceof HTMLElement)) {
                return null;
            }

            const headerRect = header.getBoundingClientRect();
            const navigationRect = navigation.getBoundingClientRect();

            return {
                headerDisplay: getComputedStyle(header).display,
                headerGridTemplateAreas: getComputedStyle(header).gridTemplateAreas,
                headerMinHeight: getComputedStyle(header).minHeight,
                navigationGridArea: getComputedStyle(navigation).gridArea,
                navigationPosition: getComputedStyle(navigation).position,
                navigationTop: Math.round(navigationRect.top),
                headerTop: Math.round(headerRect.top),
                primaryDisplay: getComputedStyle(primary).display,
                tableContainerPosition: getComputedStyle(tableContainer).position,
                tableContainerOverflowX: getComputedStyle(tableContainer).overflowX,
                gridMinWidth: getComputedStyle(grid).minWidth,
                documentScrollWidth: document.documentElement.scrollWidth,
                viewportWidth: window.innerWidth,
            };
        });

        expect(metrics).not.toBeNull();
        expect(metrics?.headerDisplay).toBe('grid');
        expect(metrics?.headerGridTemplateAreas).toContain('navigation');
        expect(metrics?.headerMinHeight).toBe('0px');
        expect(metrics?.navigationGridArea).toBe('navigation');
        expect(metrics?.navigationPosition).toBe('relative');
        expect(metrics?.navigationTop).toBeGreaterThanOrEqual(metrics?.headerTop ?? 0);
        expect(metrics?.primaryDisplay).toBe('flex');
        expect(metrics?.tableContainerPosition).toBe('static');
        expect(metrics?.tableContainerOverflowX).toBe('auto');
        expect(metrics?.gridMinWidth).not.toBe('0px');
        expect(metrics?.documentScrollWidth).toBeLessThanOrEqual(metrics?.viewportWidth ?? 0);
    });
});
