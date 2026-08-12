import { test, expect } from '@playwright/test';
import { dialogOverlayMountDomId } from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from './timeouts';
import {
    expectContainerToManageHorizontalOverflow,
    expectDialogToFitViewport,
    expectNoHorizontalViewportOverflow,
    ensureRosterLayout,
    gotoWhenReady,
    loginAs,
    openNewLeaveRequestDialog,
    loginAsPrivilegedUserWithSeededPasskeySession,
    openAuthenticatedNavIfCollapsed,
    openRoster,
    openTimesheetSettings,
    resetTimesheetDisplayPreferences,
    webauthnBaseURL,
} from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

test.describe('Mobile experience smoke', () => {
    test.afterEach(() => resetTimesheetDisplayPreferences('e2e-test@example.com'));

    test('support impersonation selector works in collapsed navigation without horizontal overflow', async ({ page }) => {
        await loginAsPrivilegedUserWithSeededPasskeySession(
            page,
            'e2e-super-admin@example.com',
            'test-password-123',
        );
        await openRoster(page, {
            email: 'e2e-super-admin@example.com',
            password: 'test-password-123',
            ensureEditable: false,
            useCurrentSession: true,
        });

        await openAuthenticatedNavIfCollapsed(page);
        const userSwitcher = page.locator('#support-impersonation-user-mobile');
        await expect(userSwitcher).toBeVisible();
        await expect(userSwitcher).toContainText('Super admin');
        await expect(userSwitcher).toContainText('Alpha — Worker');
        await expect(userSwitcher).not.toContainText('@');
        await expectNoHorizontalViewportOverflow(page);

        await userSwitcher.selectOption({ label: 'Alpha — Worker' });
        await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWindow)/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#roster-week-shell')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await openAuthenticatedNavIfCollapsed(page);
        await expect(page.locator('#support-impersonation-user-mobile option:checked')).toHaveText('Alpha — Worker');
        await expect(page.getByRole('link', { name: 'Support', exact: true })).toBeVisible();
        await expectNoHorizontalViewportOverflow(page);

        await page.locator('#support-impersonation-user-mobile').selectOption({ label: 'Super admin' });
        await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWindow)/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#roster-week-shell')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await openAuthenticatedNavIfCollapsed(page);
        await expect(page.locator('#support-impersonation-user-mobile option:checked')).toHaveText('Super admin');
        await expectNoHorizontalViewportOverflow(page);
    });

    test('venue admin navigation remains usable when the header collapses', async ({ page }) => {
        await loginAsPrivilegedUserWithSeededPasskeySession(page);

        const navToggle = page.locator('.navbar-toggler');
        if (await navToggle.isVisible()) {
            await expect(navToggle).toBeVisible();
            const headerMetrics = await page.locator('.app-header-navbar').evaluate((navbar) => {
                if (!(navbar instanceof HTMLElement)) {
                    throw new Error('Expected app header navbar to be an HTMLElement');
                }

                const brand = navbar.querySelector('.navbar-brand');
                const toggle = navbar.querySelector('.app-mobile-menu-toggle');
                if (!(brand instanceof HTMLElement) || !(toggle instanceof HTMLElement)) {
                    throw new Error('Expected mobile header brand and toggle controls');
                }

                const navRect = navbar.getBoundingClientRect();
                const brandRect = brand.getBoundingClientRect();
                const toggleRect = toggle.getBoundingClientRect();
                return {
                    viewportWidth: window.innerWidth,
                    documentScrollLeft: document.documentElement.scrollLeft,
                    bodyScrollLeft: document.body.scrollLeft,
                    navLeft: Math.round(navRect.left),
                    navRight: Math.round(navRect.right),
                    brandInset: Math.round(brandRect.left - navRect.left),
                    toggleInset: Math.round(navRect.right - toggleRect.right),
                    toggleRight: Math.round(toggleRect.right),
                };
            });

            expect(headerMetrics.documentScrollLeft).toBe(0);
            expect(headerMetrics.bodyScrollLeft).toBe(0);
            expect(headerMetrics.navLeft).toBeGreaterThanOrEqual(0);
            expect(headerMetrics.navRight).toBeLessThanOrEqual(headerMetrics.viewportWidth + 1);
            expect(headerMetrics.brandInset).toBeGreaterThanOrEqual(8);
            expect(headerMetrics.toggleInset).toBeGreaterThanOrEqual(8);
            expect(headerMetrics.viewportWidth - headerMetrics.toggleRight).toBeLessThanOrEqual(20);
        }

        const openedDrawer = await openAuthenticatedNavIfCollapsed(page);
        if (openedDrawer) {
            const mobileNav = page.locator('#app-mobile-nav');
            await expect(mobileNav).toBeVisible();
            await expect(mobileNav.getByRole('link', { name: 'Roster', exact: true })).toHaveAttribute('aria-current', 'page');
            await expect(mobileNav.getByRole('link', { name: 'Timesheets' })).toBeVisible();
            await expect(mobileNav.getByRole('link', { name: 'Unavailability' })).toBeVisible();
            await expect(mobileNav.getByRole('link', { name: 'Admin' })).toBeVisible();
            await expect(mobileNav.getByRole('button', { name: 'Logout' })).toBeVisible();

            const drawerMetrics = await mobileNav.evaluate((drawer) => {
                if (!(drawer instanceof HTMLElement)) {
                    throw new Error('Expected mobile nav drawer to be an HTMLElement');
                }

                const firstLink = drawer.querySelector('.app-mobile-nav-link');
                if (!(firstLink instanceof HTMLElement)) {
                    throw new Error('Expected mobile nav link to be an HTMLElement');
                }

                const drawerRect = drawer.getBoundingClientRect();
                const linkRect = firstLink.getBoundingClientRect();
                return {
                    drawerLeft: Math.round(drawerRect.left),
                    drawerRight: Math.round(drawerRect.right),
                    drawerHeight: Math.round(drawerRect.height),
                    viewportHeight: window.innerHeight,
                    viewportWidth: window.innerWidth,
                    linkHeight: Math.round(linkRect.height),
                    linkDisplay: getComputedStyle(firstLink).display,
                };
            });

            expect(drawerMetrics.drawerLeft).toBeGreaterThanOrEqual(0);
            expect(drawerMetrics.drawerRight).toBeLessThanOrEqual(drawerMetrics.viewportWidth);
            expect(drawerMetrics.drawerHeight).toBeGreaterThanOrEqual(drawerMetrics.viewportHeight - 1);
            expect(drawerMetrics.linkHeight).toBeGreaterThanOrEqual(44);
            expect(drawerMetrics.linkDisplay).toBe('flex');
            await mobileNav.getByRole('button', { name: 'Close navigation menu' }).click();
            await expect(mobileNav).toBeHidden();

            await openAuthenticatedNavIfCollapsed(page);
            await page.locator('#app-mobile-nav').getByRole('link', { name: 'Unavailability' }).click();
        } else {
            await expect(page.getByRole('link', { name: 'roster', exact: true })).toHaveAttribute('aria-current', 'page');
            await expect(page.getByRole('link', { name: 'timesheets' })).toBeVisible();
            await expect(page.getByRole('link', { name: 'unavailability' })).toBeVisible();
            await expect(page.getByRole('link', { name: 'admin' })).toBeVisible();
            await page.getByRole('link', { name: 'unavailability' }).click();
        }
        await expect(page).toHaveURL(/LeaveRequests/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#leave-requests-content')).toBeVisible();

        const reopenedDrawer = await openAuthenticatedNavIfCollapsed(page);
        if (reopenedDrawer) {
            await page.locator('#app-mobile-nav').getByRole('link', { name: 'Timesheets' }).click();
        } else {
            await page.getByRole('link', { name: 'timesheets' }).click();
        }
        await expect(page).toHaveURL(/(Timesheets|ShowTimesheetWindow)/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#timesheet-week-shell')).toBeVisible();
    });

    test('worker mobile navigation uses profile for unavailability access and hides the unavailability header link @canonical-mobile', async ({ page }) => {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');

        const openedDrawer = await openAuthenticatedNavIfCollapsed(page);
        if (openedDrawer) {
            const mobileNav = page.locator('#app-mobile-nav');
            await expect(mobileNav.getByRole('link', { name: 'Roster', exact: true })).toBeVisible();
            await expect(mobileNav.getByRole('link', { name: 'Profile' })).toBeVisible();
            await expect(mobileNav.getByRole('link', { name: 'Timesheets' })).toBeVisible();
            await expect(mobileNav.getByRole('link', { name: 'Unavailability' })).toHaveCount(0);
            await expect(mobileNav.getByRole('link', { name: 'Admin' })).toHaveCount(0);

            await mobileNav.getByRole('link', { name: 'Profile' }).click();
        } else {
            await expect(page.getByRole('link', { name: 'roster', exact: true })).toBeVisible();
            await expect(page.getByRole('link', { name: 'profile' })).toBeVisible();
            await expect(page.getByRole('link', { name: 'timesheets' })).toBeVisible();
            await expect(page.getByRole('link', { name: 'unavailability' })).toHaveCount(0);
            await expect(page.getByRole('link', { name: 'admin' })).toHaveCount(0);

            await page.getByRole('link', { name: 'profile' }).click();
        }
        await expect(page).toHaveURL(/EditProfile/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#profile-content-fragment')).toBeVisible();

        const leaveSectionToggle = page.getByRole('button', { name: 'Unavailability' });
        if ((await leaveSectionToggle.getAttribute('aria-expanded')) !== 'true') {
            await leaveSectionToggle.click();
        }

        await expect(page.locator('#self-service-leave-form-fragment')).toBeVisible();
        await expect(page.locator('#self-service-leave-history-fragment')).toBeVisible();
        await expectNoHorizontalViewportOverflow(page);
    });

    test('roster creator remains usable on a narrow viewport without leaking page-level overflow', async ({ page }) => {
        await openRoster(page);
        await expect(page.locator('.roster-grid')).toBeVisible();

        const firstDaySection = page.locator('[data-roster-day-section]').first();
        const dayRows = firstDaySection.locator('[data-roster-row]').filter({ has: page.locator('[data-roster-shift-launcher="true"]') });
        const initialRowCount = await dayRows.count();

        await expectContainerToManageHorizontalOverflow(page, '.roster-slots-scroller');
        await expectNoHorizontalViewportOverflow(page);

        const addButton = page.locator('[data-roster-day-add="true"]').first();
        await addButton.evaluate((button: HTMLButtonElement) => button.click());
        await expect(dayRows).toHaveCount(initialRowCount + 1);
        await expectNoHorizontalViewportOverflow(page);
    });

    test('unavailability opens a phone-sized workflow dialog that fits the viewport', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/LeaveRequests', '#leave-requests-content');

        await expect(page.locator('#leave-requests-content')).toBeVisible();
        await expectNoHorizontalViewportOverflow(page);

        await openNewLeaveRequestDialog(page);
        await expectDialogToFitViewport(page, `#${dialogOverlayMountDomId} .modal-dialog, #${dialogOverlayMountDomId} [role="dialog"]`);
    });

    test('timesheet creation dialog remains usable on a phone-sized viewport', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');

        await expect(page.locator('[data-timesheet-operational-date]').first()).toBeVisible();
        await expectContainerToManageHorizontalOverflow(page, '.timesheet-week-frame');
        await expectNoHorizontalViewportOverflow(page);

        const addBar = page.locator('[data-timesheet-day-add="true"]').first();
        await expect(addBar).toBeVisible();
        await addBar.click();
        await expect(page.locator('#timesheet-entry-create-form')).toBeVisible();
        await expectDialogToFitViewport(page, `#${dialogOverlayMountDomId} .modal-dialog, #${dialogOverlayMountDomId} [role="dialog"]`);
    });

    test('timesheet day columns do not auto-scroll initially and snap to the nearest day after user scroll', async ({ page }) => {
        await page.setViewportSize({ width: 390, height: 844 });
        await page.emulateMedia({ reducedMotion: 'reduce' });
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');

        await expect(page.locator('[data-timesheet-operational-date]').first()).toBeVisible();

        const snapMetrics = await page.locator('.timesheet-week-frame').first().evaluate(async (frame) => {
            if (!(frame instanceof HTMLElement)) {
                throw new Error('Expected timesheet week frame to be an HTMLElement');
            }

            const panels = Array.from(frame.querySelectorAll('.timesheet-day-panel')).filter((panel): panel is HTMLElement => panel instanceof HTMLElement);
            if (panels.length < 3) {
                throw new Error('Expected multiple timesheet day panels');
            }

            await new Promise((resolve) => window.requestAnimationFrame(resolve));
            const initialScrollLeft = frame.scrollLeft;
            const maxScrollLeft = Math.max(0, frame.scrollWidth - frame.clientWidth);
            const secondPanelTarget = panels[1].offsetLeft + (panels[1].offsetWidth / 2) - (frame.clientWidth / 2);
            const rawScrollLeft = Math.min(Math.max(0, secondPanelTarget - (panels[1].offsetWidth * 0.32)), maxScrollLeft);

            frame.scrollLeft = rawScrollLeft;
            const frameRectBeforeSnap = frame.getBoundingClientRect();
            const secondPanelRectBeforeSnap = panels[1].getBoundingClientRect();
            const expectedScrollLeft = Math.min(
                Math.max(
                    0,
                    frame.scrollLeft
                        + (secondPanelRectBeforeSnap.left + (secondPanelRectBeforeSnap.width / 2))
                        - (frameRectBeforeSnap.left + (frameRectBeforeSnap.width / 2)),
                ),
                maxScrollLeft,
            );
            frame.dispatchEvent(new Event('scroll', { bubbles: false }));

            await new Promise((resolve) => window.setTimeout(resolve, 260));

            const frameRect = frame.getBoundingClientRect();
            const frameCenter = frameRect.left + (frameRect.width / 2);
            const nearestPanel = panels.reduce((nearest, panel) => {
                const panelRect = panel.getBoundingClientRect();
                const panelCenter = panelRect.left + (panelRect.width / 2);
                const distance = Math.abs(panelCenter - frameCenter);
                if (!nearest || distance < nearest.distance) {
                    return { index: panels.indexOf(panel), distance, centerOffset: panelCenter - frameCenter };
                }
                return nearest;
            }, null as null | { index: number; distance: number; centerOffset: number });

            return {
                initialScrollLeft,
                panelCount: panels.length,
                clientWidth: frame.clientWidth,
                scrollWidth: frame.scrollWidth,
                expectedScrollLeft,
                actualScrollLeft: frame.scrollLeft,
                nearestIndex: nearestPanel?.index ?? -1,
                nearestCenterOffset: nearestPanel?.centerOffset ?? Number.NaN,
                snapType: getComputedStyle(frame).scrollSnapType,
                panelSnapAlign: getComputedStyle(panels[1]).scrollSnapAlign,
            };
        });

        expect(snapMetrics.initialScrollLeft).toBe(0);
        expect(snapMetrics.panelCount).toBeGreaterThan(1);
        expect(snapMetrics.scrollWidth).toBeGreaterThan(snapMetrics.clientWidth);
        expect(snapMetrics.snapType).toContain('mandatory');
        expect(snapMetrics.panelSnapAlign).toBe('center');
        expect(snapMetrics.nearestIndex).toBe(1);
        expect(Math.abs(snapMetrics.actualScrollLeft - snapMetrics.expectedScrollLeft)).toBeLessThanOrEqual(2);
        expect(Math.abs(snapMetrics.nearestCenterOffset)).toBeLessThanOrEqual(2);

        const centeredDayAddBar = page.locator('[data-timesheet-operational-date]').nth(1).locator('[data-timesheet-day-add="true"]');
        await expect(centeredDayAddBar).toBeVisible();
        await centeredDayAddBar.click();
        await expect(page.locator('#timesheet-entry-create-form')).toBeVisible();
    });

    test('timesheet day snapping lets the newest quick scroll win', async ({ page }) => {
        await page.setViewportSize({ width: 390, height: 844 });
        await page.emulateMedia({ reducedMotion: 'reduce' });
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');

        await expect(page.locator('[data-timesheet-operational-date]').first()).toBeVisible();

        const snapMetrics = await page.locator('.timesheet-week-frame').first().evaluate(async (frame) => {
            if (!(frame instanceof HTMLElement)) {
                throw new Error('Expected timesheet week frame to be an HTMLElement');
            }

            const panels = Array.from(frame.querySelectorAll('.timesheet-day-panel')).filter((panel): panel is HTMLElement => panel instanceof HTMLElement);
            if (panels.length < 4) {
                throw new Error('Expected at least four timesheet day panels');
            }

            const maxScrollLeft = Math.max(0, frame.scrollWidth - frame.clientWidth);
            const scrollNearPanel = (panel: HTMLElement, adjustmentRatio: number) => {
                const centeredLeft = panel.offsetLeft + (panel.offsetWidth / 2) - (frame.clientWidth / 2);
                frame.scrollLeft = Math.min(Math.max(0, centeredLeft + (panel.offsetWidth * adjustmentRatio)), maxScrollLeft);
                frame.dispatchEvent(new Event('scroll', { bubbles: false }));
            };

            scrollNearPanel(panels[1], -0.2);
            await new Promise((resolve) => window.setTimeout(resolve, 60));
            scrollNearPanel(panels[2], -0.2);
            await new Promise((resolve) => window.setTimeout(resolve, 300));

            const frameRect = frame.getBoundingClientRect();
            const frameCenter = frameRect.left + (frameRect.width / 2);
            const nearestPanel = panels.reduce((nearest, panel) => {
                const panelRect = panel.getBoundingClientRect();
                const panelCenter = panelRect.left + (panelRect.width / 2);
                const distance = Math.abs(panelCenter - frameCenter);
                if (!nearest || distance < nearest.distance) {
                    return { index: panels.indexOf(panel), distance, centerOffset: panelCenter - frameCenter };
                }
                return nearest;
            }, null as null | { index: number; distance: number; centerOffset: number });

            return {
                nearestIndex: nearestPanel?.index ?? -1,
                nearestCenterOffset: nearestPanel?.centerOffset ?? Number.NaN,
                snapDragging: frame.classList.contains('is-horizontal-snap-dragging'),
                dragDragging: frame.classList.contains('is-horizontal-dragging'),
            };
        });

        expect(snapMetrics.nearestIndex).toBe(2);
        expect(Math.abs(snapMetrics.nearestCenterOffset)).toBeLessThanOrEqual(2);
        expect(snapMetrics.snapDragging).toBe(false);
        expect(snapMetrics.dragDragging).toBe(false);
    });

    test('roster assignment filters preserve horizontal scroll in both layouts', async ({ page }) => {
        test.setTimeout(E2E_TIMEOUT.slowTest);
        await page.setViewportSize({ width: 390, height: 844 });
        await page.emulateMedia({ reducedMotion: 'reduce' });

        const setScroll = async (selector: string) => page.locator(selector).first().evaluate((element) => {
            if (!(element instanceof HTMLElement)) {
                throw new Error('Expected roster scroll frame to be an HTMLElement');
            }
            const maxScrollLeft = Math.max(0, element.scrollWidth - element.clientWidth);
            if (maxScrollLeft <= 0) return 0;
            element.scrollLeft = Math.min(Math.max(90, element.clientWidth * 0.8), maxScrollLeft);
            return element.scrollLeft;
        });
        const readScroll = async (selector: string) => page.locator(selector).first().evaluate((element) => {
            if (!(element instanceof HTMLElement)) {
                throw new Error('Expected roster scroll frame to be an HTMLElement');
            }
            return element.scrollLeft;
        });
        const markScrollOwner = async (selector: string, marker: string) => page.locator(selector).first().evaluate((element, markerValue) => {
            if (!(element instanceof HTMLElement)) {
                throw new Error('Expected roster scroll frame to be an HTMLElement');
            }
            element.dataset.e2eScrollOwnerMarker = markerValue;
        }, marker);
        const toggleAssignmentFilter = async (label: string) => {
            const filterForm = page.locator('form[data-roster-filter-form="true"]');
            const filterLabel = filterForm.locator('label', { hasText: label });
            const inputId = await filterLabel.getAttribute('for');
            if (!inputId) throw new Error(`Expected input id for roster filter ${label}`);
            const responsePromise = page.waitForResponse((response) => (
                response.request().method() === 'POST'
                && response.url().includes('/UpdateRosterAssignmentFilters')
            ));
            await filterForm.evaluate((form, selectedInputId) => {
                if (!(form instanceof HTMLFormElement)) throw new Error('Expected roster filter form');
                const input = form.querySelector(`#${selectedInputId}`);
                if (!(input instanceof HTMLInputElement)) throw new Error('Expected roster filter checkbox');
                input.checked = !input.checked;
                const htmx = (window as Window & {
                    htmx?: { ajax: (method: string, url: string, options: { values: Record<string, string>; swap: string }) => unknown };
                }).htmx;
                if (!htmx) throw new Error('Expected htmx runtime');
                const values = Object.fromEntries(new FormData(form).entries()) as Record<string, string>;
                htmx.ajax('POST', form.action, { values, swap: 'none' });
            }, inputId);
            await responsePromise;
            await expect(page.locator('#roster-grid-frame')).toBeVisible();
        };

        await openRoster(page, { rosterLayoutMode: 'day_columns' });
        await expect(page.locator('.roster-day-columns')).toBeVisible();
        const dayColumnsScroll = await setScroll('#roster-grid-frame');
        await markScrollOwner('#roster-grid-frame', 'day-columns-owner');
        await toggleAssignmentFilter('Too many shifts');
        if (dayColumnsScroll > 0) {
            expect(await readScroll('#roster-grid-frame')).toBeGreaterThanOrEqual(0);
        }

        await markScrollOwner('#roster-grid-frame', 'day-columns-close-owner');
        const closeResponsePromise = page.waitForResponse((response) => (
            response.request().method() === 'POST'
            && response.url().includes('/ToggleRosterDayClosed')
        ));
        await page.locator('[data-roster-day-closed-toggle="true"]').first().evaluate((button) => {
            const form = button.closest('form');
            if (!(form instanceof HTMLFormElement)) throw new Error('Expected day closed toggle form');
            form.requestSubmit();
        });
        await closeResponsePromise;
        if (dayColumnsScroll > 0) {
            expect(await readScroll('#roster-grid-frame')).toBeGreaterThanOrEqual(0);
        }

        await ensureRosterLayout(page, 'day_rows');
        await expect(page.locator('.roster-slots-scroller')).toBeVisible();
        const dayRowsScroll = await setScroll('.roster-slots-scroller');
        await markScrollOwner('.roster-slots-scroller', 'day-rows-owner');
        await toggleAssignmentFilter('Regular day off');
        if (dayRowsScroll > 0) {
            expect(await readScroll('.roster-slots-scroller')).toBeGreaterThanOrEqual(0);
        }
    });

    test('timesheet filter and week navigation preserve horizontal scroll', async ({ page }) => {
        resetTimesheetDisplayPreferences('e2e-test@example.com');
        await page.setViewportSize({ width: 390, height: 844 });
        await page.emulateMedia({ reducedMotion: 'reduce' });
        await loginAsPrivilegedUserWithSeededPasskeySession(page);
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');

        const frame = page.locator('.timesheet-week-frame').first();
        await expect(frame).toBeVisible();
        await expect(page.locator('#timesheet-day-columns')).toBeVisible();

        const setScroll = async () => frame.evaluate((element) => {
            if (!(element instanceof HTMLElement)) {
                throw new Error('Expected timesheet week frame to be an HTMLElement');
            }
            const maxScrollLeft = Math.max(0, element.scrollWidth - element.clientWidth);
            element.scrollLeft = Math.min(Math.max(120, element.clientWidth * 1.4), maxScrollLeft);
            return element.scrollLeft;
        });
        const readScroll = async () => frame.evaluate((element) => {
            if (!(element instanceof HTMLElement)) {
                throw new Error('Expected timesheet week frame to be an HTMLElement');
            }
            return element.scrollLeft;
        });

        const beforeFilterScroll = await setScroll();
        expect(beforeFilterScroll).toBeGreaterThan(0);

        await openTimesheetSettings(page);
        await page.locator('label', { hasText: 'Show suggestions' }).click();
        await expect(page.locator('#timesheet-day-columns')).toBeVisible();
        await expect(page.locator('#timesheet-week-toolbar')).toBeVisible();
        const afterFilterScroll = await readScroll();
        expect(Math.abs(afterFilterScroll - beforeFilterScroll)).toBeLessThanOrEqual(2);

        const beforeWeekScroll = await setScroll();
        const previousAnchorDate = new URL(page.url()).searchParams.get('anchorDate');
        await page.locator('.app-week-nav-group').getByRole('link', { name: '>' }).click();
        await expect(page).toHaveURL((url) =>
            url.pathname === '/ShowTimesheetWindow'
            && url.searchParams.has('anchorDate')
            && url.searchParams.get('anchorDate') !== previousAnchorDate,
        { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#timesheet-day-columns')).toBeVisible();
        const afterWeekScroll = await readScroll();
        expect(Math.abs(afterWeekScroll - beforeWeekScroll)).toBeLessThanOrEqual(2);

        const surfaceConfig = await page.locator('#timesheet-week-shell [data-bepis-surface-config]').getAttribute('data-bepis-surface-config');
        expect(surfaceConfig).toContain('timesheets');
        expect(surfaceConfig).toContain('timesheet-day-columns');
        resetTimesheetDisplayPreferences('e2e-test@example.com');
    });

    test('timesheet entries use uniform mobile actions for approved and pending entries @canonical-mobile', async ({ page }) => {
        resetTimesheetDisplayPreferences('e2e-test@example.com');
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');
        await openTimesheetSettings(page);
        const hideApproved = page.getByRole('checkbox', { name: 'Hide approved' });
        if (await hideApproved.isChecked()) {
            await hideApproved.locator('..').click();
        }

        const approvedEntry = page.locator('[data-timesheet-entry-approved="true"]').first();
        const pendingEntry = page.locator('[data-timesheet-entry-approved="false"]').first();

        await expect(approvedEntry).toBeVisible();
        await expect(pendingEntry).toBeVisible();
        await expect(approvedEntry.getByRole('button', { name: 'Approved' })).toBeVisible();
        await expect(pendingEntry.getByRole('button', { name: 'Approve' })).toBeVisible();
        await expect(approvedEntry.locator('.timesheet-entry-actions .btn:has-text("Edit")')).toHaveCount(0);
        await expect(pendingEntry.locator('.timesheet-entry-actions .btn:has-text("Edit")')).toHaveCount(0);
        await expect(approvedEntry.getByRole('link', { name: /Edit timesheet entry for/ })).toHaveCount(1);
        await expect(pendingEntry.getByRole('link', { name: /Edit timesheet entry for/ })).toHaveCount(1);
        await expect(page.locator('.timesheet-shape-bar').first()).toBeVisible();
        resetTimesheetDisplayPreferences('e2e-test@example.com');
    });
});
