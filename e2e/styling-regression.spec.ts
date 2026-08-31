import { test, expect, Page } from '@playwright/test';
import {
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
import { gotoWhenReady } from './support/runtime';
import { loginAs } from './support/session';
import { openRoster } from './support/roster';
import { E2E_TIMEOUT } from './timeouts';

async function expectLocalStylesheet(page: Page, path: string) {
    await expect(page.locator(`link[rel="stylesheet"][href*="${path}"]`)).toHaveCount(1);
    const response = await page.request.get(path);
    expect(response.ok()).toBeTruthy();
    expect(response.headers()['content-type']).toContain('text/css');
}

test.describe('Styling regression contracts', () => {
    test.use({ viewport: { width: 1280, height: 900 } });

    test('keeps the rendered desktop roster contained, scrollable, and aligned', async ({ page }) => {
        await openRoster(page, { ensureEditable: false });

        await expectLocalStylesheet(page, '/css/components/panels.css');
        await expectLocalStylesheet(page, '/css/features/roster/grid-frame.css');

        const metrics = await page.locator('.roster-grid-frame').first().evaluate((frame) => {
            if (!(frame instanceof HTMLElement)) throw new Error('Expected roster grid frame');
            const scroller = frame.querySelector('.roster-slots-scroller');
            const grid = frame.querySelector('.roster-grid');
            if (!(scroller instanceof HTMLElement) || !(grid instanceof HTMLElement)) {
                throw new Error('Expected rendered roster grid and scroller');
            }

            const railSections = Array.from(frame.querySelectorAll('.roster-day-rail-section'));
            const gridSections = Array.from(frame.querySelectorAll('.roster-grid-day-section'));
            return {
                overflowX: getComputedStyle(scroller).overflowX,
                tableScrollWidth: scroller.scrollWidth,
                tableClientWidth: scroller.clientWidth,
                frameScrollWidth: frame.scrollWidth,
                frameClientWidth: frame.clientWidth,
                gridHasMinimumWidth: getComputedStyle(grid).minWidth !== '0px',
                sectionCount: gridSections.length,
                alignedSections: railSections.length === gridSections.length
                    && railSections.every((railSection, index) => {
                        const gridSection = gridSections[index];
                        if (!(railSection instanceof HTMLElement) || !(gridSection instanceof HTMLElement)) return false;
                        const railRect = railSection.getBoundingClientRect();
                        const gridRect = gridSection.getBoundingClientRect();
                        return Math.max(
                            Math.abs(railRect.top - gridRect.top),
                            Math.abs(railRect.bottom - gridRect.bottom),
                        ) <= 1;
                    }),
            };
        });

        expect(metrics.overflowX).toBe('auto');
        expect(metrics.tableScrollWidth).toBeGreaterThanOrEqual(metrics.tableClientWidth);
        expect(metrics.frameScrollWidth).toBeLessThanOrEqual(metrics.frameClientWidth + 1);
        expect(metrics.gridHasMinimumWidth).toBe(true);
        expect(metrics.sectionCount).toBeGreaterThan(0);
        expect(metrics.alignedSections).toBe(true);
    });

    test('renders one shared accordion component smoke on the profile page', async ({ page }) => {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await gotoWhenReady(page, '/EditProfile?section=profile', '#profile-sections');
        await expectLocalStylesheet(page, '/css/components/accordions.css');

        const openItem = page.locator('#profile-sections .accordion-item:has(.accordion-button:not(.collapsed))').first();
        const collapsedItem = page.locator('#profile-sections .accordion-item:has(.accordion-button.collapsed)').first();
        await expect(openItem.locator('.accordion-button')).toHaveAttribute('aria-expanded', 'true');
        await expect(openItem.locator('.accordion-collapse')).toBeVisible();
        await expect(collapsedItem.locator('.accordion-button')).toHaveAttribute('aria-expanded', 'false');
        await expect(collapsedItem.locator('.accordion-collapse')).toBeHidden();
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

        const preferencesForm = page.locator('#profile-shift-preferences-form');
        const preferencesTargetSelector = await preferencesForm.getAttribute('hx-target');
        if (preferencesTargetSelector === null) throw new Error('Expected a shift-preferences HTMX target');
        const capturePreferencesTarget = async () => {
            const target = await page.locator(preferencesTargetSelector).elementHandle();
            if (target === null) throw new Error('Expected a mounted shift-preferences target');
            return target;
        };
        const expectPreferencesTargetReplaced = (target: Awaited<ReturnType<typeof capturePreferencesTarget>>) =>
            expect.poll(
                () => target.evaluate((element) => element.isConnected),
                { timeout: E2E_TIMEOUT.liveUpdate },
            ).toBe(false);

        const availabilityInput = firstRange.locator(`[${orderedRangeAvailabilityDomAttr}] input[type="checkbox"]`);
        if (!(await availabilityInput.isChecked())) {
            const previousPreferencesTarget = await capturePreferencesTarget();
            const availabilityResponsePromise = page.waitForResponse((response) =>
                response.request().method() === 'POST' && response.url().includes('/UpdateProfile'),
            );
            await firstRange.locator(`[${orderedRangeAvailabilityDomAttr}] label`).click();
            const availabilityResponse = await availabilityResponsePromise;
            expect(availabilityResponse.status(), await availabilityResponse.text()).toBe(200);
            await availabilityResponse.finished();
            await expectPreferencesTargetReplaced(previousPreferencesTarget);
        }

        const startInput = firstRange.locator(`[${orderedRangeStartDomAttr}]`);
        const endInput = firstRange.locator(`[${orderedRangeEndDomAttr}]`);
        await expect(startInput).toHaveAccessibleName('Earliest preferred start');
        await expect(endInput).toHaveAccessibleName('Latest preferred start');
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

        const previousEnabledPreferencesTarget = await capturePreferencesTarget();
        const disableResponsePromise = page.waitForResponse((response) =>
            response.request().method() === 'POST' && response.url().includes('/UpdateProfile'),
        );
        await firstRange.locator(`[${orderedRangeAvailabilityDomAttr}] label`).click();
        await disableResponsePromise.then((response) => response.finished());
        await expectPreferencesTargetReplaced(previousEnabledPreferencesTarget);
        await expect(startInput).toBeDisabled();
        await expect(endInput).toBeDisabled();

        const previousDisabledPreferencesTarget = await capturePreferencesTarget();
        const enableResponsePromise = page.waitForResponse((response) =>
            response.request().method() === 'POST' && response.url().includes('/UpdateProfile'),
        );
        await firstRange.locator(`[${orderedRangeAvailabilityDomAttr}] label`).click();
        await enableResponsePromise.then((response) => response.finished());
        await expectPreferencesTargetReplaced(previousDisabledPreferencesTarget);
        await expect(startInput).toBeEnabled();
        await expect(endInput).toBeEnabled();

        await page.evaluate(() => window.scrollTo(0, 240));
        const requestScrollYPromise = page.evaluate(() => new Promise<number>((resolve) => {
            document.addEventListener('htmx:beforeRequest', () => resolve(window.scrollY), { once: true });
        }));
        const swappedScrollYPromise = page.evaluate(() => new Promise<number>((resolve) => {
            document.addEventListener('htmx:afterSwap', () => resolve(window.scrollY), { once: true });
        }));
        const submittedStartValue = config.defaultStartValue + config.stepValue;
        if (submittedStartValue > config.defaultEndValue) throw new Error('Expected room to advance the default start value');
        const previousAdjustedPreferencesTarget = await capturePreferencesTarget();
        await startInput.focus();
        const [request, , , requestScrollY, swappedScrollY] = await Promise.all([
            page.waitForRequest((candidate) => candidate.url().includes('/UpdateProfile') && candidate.method() === 'POST'),
            page.waitForResponse((response) => response.url().includes('/UpdateProfile') && response.request().method() === 'POST'),
            startInput.press('ArrowRight'),
            requestScrollYPromise,
            swappedScrollYPromise,
        ]);
        await expectPreferencesTargetReplaced(previousAdjustedPreferencesTarget);
        const submitted = new URLSearchParams(request.postData() ?? '');
        expect(submitted.get(startName)).toBe(String(submittedStartValue));
        expect(submitted.get(endName)).toBe(String(config.defaultEndValue));
        await expect(page.locator('#profile-content-fragment')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });

        const refreshedStart = page.locator(`[${orderedRangeStartDomAttr}][name="${startName}"]`);
        const refreshedEnd = page.locator(`[${orderedRangeEndDomAttr}][name="${endName}"]`);
        await expect(refreshedStart).toHaveValue(String(submittedStartValue));
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

        expect(swappedScrollY).toBeGreaterThanOrEqual(Math.max(0, requestScrollY - 120));
    });

    test('keeps roster navigation and the grid contained on phone widths', async ({ page }) => {
        await page.setViewportSize({ width: 390, height: 844 });
        await openRoster(page, { email: 'e2e-test@example.com', ensureEditable: true });

        const header = page.locator('.roster-grid-header');
        const navigation = header.locator('.app-week-toolbar-navigation');
        const primary = header.locator('.app-week-toolbar-primary');
        await expect(header).toBeVisible();
        await expect(navigation).toBeVisible();
        await expect(primary).toBeVisible();

        const metrics = await page.locator('.roster-slots-scroller').evaluate((scroller) => {
            if (!(scroller instanceof HTMLElement)) throw new Error('Expected roster scroller');
            const grid = scroller.querySelector('.roster-grid');
            const header = document.querySelector('.roster-grid-header');
            const navigation = header?.querySelector('.app-week-toolbar-navigation');
            if (!(grid instanceof HTMLElement) || !(header instanceof HTMLElement) || !(navigation instanceof HTMLElement)) {
                throw new Error('Expected rendered phone roster structure');
            }
            const headerRect = header.getBoundingClientRect();
            const navigationRect = navigation.getBoundingClientRect();
            return {
                overflowX: getComputedStyle(scroller).overflowX,
                tableScrollWidth: scroller.scrollWidth,
                tableClientWidth: scroller.clientWidth,
                navigationBelowHeaderTop: navigationRect.top >= headerRect.top,
                navigationInsideViewport: navigationRect.left >= 0 && navigationRect.right <= window.innerWidth,
                pageContained: document.documentElement.scrollWidth <= window.innerWidth,
            };
        });

        expect(metrics.overflowX).toBe('auto');
        expect(metrics.tableScrollWidth).toBeGreaterThanOrEqual(metrics.tableClientWidth);
        expect(metrics.navigationBelowHeaderTop).toBe(true);
        expect(metrics.navigationInsideViewport).toBe(true);
        expect(metrics.pageContained).toBe(true);
    });
});
