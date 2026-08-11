import { test, expect, type Locator, type Page } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { dialogOverlayMountDomId, fragmentDomAttr, pageReadyEvent, regionAfterSwapEvent, surfaceConfigDomAttr, surfaceDomAttr, toastOverlayMountDomId } from '../frontend/ts/generated/contracts';
import { defaultE2ERosterGroupId, gotoWhenReady, loginAs, openNewLeaveRequestDialog, openProfileLeaveSection, openTimesheetSettings, resetTimesheetDisplayPreferences, runSql, setFlatpickrDate } from './test-helpers';

function displayDate(isoDate: string): string {
    const [year, month, day] = isoDate.split('-');
    return `${day}/${month}/${year}`;
}

async function pickerDisplayValue(locator: Locator): Promise<string | null> {
    return locator.evaluate((input: HTMLInputElement & { _flatpickr?: { altInput?: HTMLInputElement } }) =>
        input._flatpickr?.altInput?.value ?? null
    );
}

async function login(page: Page) {
    await gotoWhenReady(page, '/NewSession', '#email');
    await page.fill('#email', 'e2e-test@example.com');
    await page.fill('#password', 'test-password-123');
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWindow)/, { timeout: E2E_TIMEOUT.navigation });
    await expect(page.locator('#roster-week-shell')).toBeVisible();
}

test.describe('HTMX submit regressions', () => {
    test.afterEach(() => resetTimesheetDisplayPreferences('e2e-test@example.com'));
    test('roster quick-view unavailability submit resets the form through live refetch', async ({ page }) => {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await gotoWhenReady(page, `/RosterWeeks?rosterGroupId=${defaultE2ERosterGroupId}`, '#self-service-leave-form');
        await expect(page.locator('#self-service-leave-form')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(page.locator('#roster-layout [data-bepis-surface="self-service-leave"]')).toBeVisible();

        const startDateBefore = await page.locator('#self-service-leave-form input[name="startDate"]').inputValue();
        const endDateBefore = await page.locator('#self-service-leave-form input[name="endDate"]').inputValue();
        await expect.poll(() => pickerDisplayValue(page.locator('#self-service-leave-form input[name="startDate"]'))).toBe(displayDate(startDateBefore));
        await expect.poll(() => pickerDisplayValue(page.locator('#self-service-leave-form input[name="endDate"]'))).toBe(displayDate(endDateBefore));

        const note = `e2e roster quick unavailable ${Date.now()}`;
        await page.locator('#self-service-leave-form textarea[name="notes"]').fill(note);
        await page.locator('#self-service-leave-form button[type="submit"]').click();

        await expect(page.locator(`#${toastOverlayMountDomId}`)).toContainText('Unavailable period submitted', { timeout: E2E_TIMEOUT.assertion });
        await expect(page.locator('#self-service-leave-form textarea[name="notes"]')).toHaveValue('', { timeout: E2E_TIMEOUT.assertion });
        await expect(page.locator('#self-service-leave-form input[name="startDate"]')).toHaveValue(startDateBefore, { timeout: E2E_TIMEOUT.assertion });
        await expect(page.locator('#self-service-leave-form input[name="endDate"]')).toHaveValue(endDateBefore, { timeout: E2E_TIMEOUT.assertion });
        await expect.poll(() => pickerDisplayValue(page.locator('#self-service-leave-form input[name="startDate"]'))).toBe(displayDate(startDateBefore));
        await expect.poll(() => pickerDisplayValue(page.locator('#self-service-leave-form input[name="endDate"]'))).toBe(displayDate(endDateBefore));
    });

    test('profile leave submit appends a leave request without nesting the whole profile page', async ({ page }) => {
        const note = 'profile-leave-submit-check';

        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await openProfileLeaveSection(page);

        const initialCount = await page.locator('#self-service-leave-history-fragment .leave-request-row').count();
        const submitResponsePromise = page.waitForResponse((response) =>
            response.request().method() === 'POST' && response.url().includes('/CreateLeaveRequest')
        );

        await setFlatpickrDate(page, '#startDate', '2026-03-23');
        await setFlatpickrDate(page, '#endDate', '2026-03-24');
        await expect.poll(() => pickerDisplayValue(page.locator('#self-service-leave-form input[name="startDate"]'))).toBe('23/03/2026');
        await expect.poll(() => pickerDisplayValue(page.locator('#self-service-leave-form input[name="endDate"]'))).toBe('24/03/2026');
        await page.fill('#notes', note);
        await page.getByRole('button', { name: 'Add unavailable time' }).click();

        const submitResponse = await submitResponsePromise;
        const submitResponseText = await submitResponse.text();
        await expect(page.locator('#self-service-leave-form-fragment')).toBeVisible();
        await expect(page.locator('#self-service-leave-history-fragment')).toContainText(note);
        await expect(page.locator('#self-service-leave-history-fragment .leave-request-row')).toHaveCount(initialCount + 1);
        await expect(page.locator('#self-service-leave-form-fragment #profile-content-fragment')).toHaveCount(0);
        await expect(page.locator('#self-service-leave-form-fragment #profile-leave')).toHaveCount(0);
        await expect.poll(() => pickerDisplayValue(page.locator('#self-service-leave-form input[name="startDate"]'))).toMatch(/^\d{2}\/\d{2}\/\d{4}$/);
        await expect.poll(() => pickerDisplayValue(page.locator('#self-service-leave-form input[name="endDate"]'))).toMatch(/^\d{2}\/\d{2}\/\d{4}$/);
        expect(submitResponseText).not.toContain('id="profile-content-fragment"');
        expect(submitResponseText).not.toContain('id="profile-leave"');
    });

    test('unavailable-period modal date fields get flatpickr after HTMX swap', async ({ page }) => {
        await login(page);
        await gotoWhenReady(page, '/LeaveRequests', '#leave-requests-content');

        await openNewLeaveRequestDialog(page);

        for (const selector of ['#startDate', '#endDate']) {
            await expect.poll(async () => {
                return page.locator(selector).evaluate((input) => {
                    const flatpickr = (input as HTMLInputElement & {
                        _flatpickr?: { altInput?: HTMLInputElement };
                    })._flatpickr;
                    const visibleInput = flatpickr?.altInput ?? (input as HTMLInputElement);
                    return Boolean(
                        flatpickr
                        && visibleInput.isConnected
                        && visibleInput.type !== 'hidden'
                        && getComputedStyle(visibleInput).display !== 'none'
                        && getComputedStyle(visibleInput).visibility !== 'hidden',
                    );
                });
            }).toBe(true);
        }
    });

    test('generic lifecycle events follow the connected OOB replacement', async ({ page }) => {
        await login(page);

        const lifecycleTargets = await page.evaluate(({ fragmentAttr, afterSwapEvent, readyEvent }) => new Promise<{ pageReadyTargetId: string; regionId: string }>((resolve, reject) => {
            const staleRegion = document.createElement('section');
            staleRegion.setAttribute(fragmentAttr, 'true');
            const staleTarget = document.createElement('div');
            staleRegion.appendChild(staleTarget);

            const replacementRegion = document.createElement('section');
            replacementRegion.id = 'connected-region';
            replacementRegion.setAttribute(fragmentAttr, 'true');
            const replacementTarget = document.createElement('div');
            replacementTarget.id = 'connected-target';
            replacementRegion.appendChild(replacementTarget);
            document.body.appendChild(replacementRegion);

            const timeout = window.setTimeout(() => {
                replacementRegion.remove();
                reject(new Error('Expected connected region lifecycle event'));
            }, 1000);
            let pageReadyTargetId = '';
            document.addEventListener(readyEvent, (event) => {
                const target = (event as CustomEvent<{ target: HTMLElement }>).detail.target;
                pageReadyTargetId = target.id;
            }, { once: true });
            document.addEventListener(afterSwapEvent, (event) => {
                window.clearTimeout(timeout);
                const region = (event as CustomEvent<{ region: HTMLElement }>).detail.region;
                replacementRegion.remove();
                resolve({ pageReadyTargetId, regionId: region.id });
            }, { once: true });
            replacementTarget.dispatchEvent(new CustomEvent('htmx:afterSwap', {
                bubbles: true,
                detail: { target: staleTarget },
            }));
        }), { fragmentAttr: fragmentDomAttr, afterSwapEvent: regionAfterSwapEvent, readyEvent: pageReadyEvent });

        expect(lifecycleTargets).toEqual({
            pageReadyTargetId: 'connected-target',
            regionId: 'connected-region',
        });
    });

    test('reports and rejects a FrontendSurface DOM/config mismatch', async ({ page }) => {
        await login(page);
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');

        const errorDetail = await page.evaluate(({ configAttr, ownerAttr, readyEvent }) => new Promise<{ error: string }>((resolve, reject) => {
            const owner = document.querySelector(`[${configAttr}]`);
            if (!(owner instanceof HTMLElement)) {
                reject(new Error('Expected a FrontendSurface mount'));
                return;
            }

            document.addEventListener('app:live-update-surface-config-failed', (event) => {
                resolve((event as CustomEvent<{ error: string }>).detail);
            }, { once: true });
            owner.setAttribute(ownerAttr, 'roster');
            document.dispatchEvent(new CustomEvent(readyEvent));
        }), {
            configAttr: surfaceConfigDomAttr,
            ownerAttr: surfaceDomAttr,
            readyEvent: pageReadyEvent,
        });

        expect(errorDetail.error).toContain('FrontendSurface DOM/config mismatch');
        await expect(page.locator('#timesheet-week-shell')).toBeVisible();
    });

    test('unavailable-period submit creates one request', async ({ page }, testInfo) => {
        const note = `single-submit-leave-check-${testInfo.repeatEachIndex}-${Date.now()}`;

        await login(page);
        await gotoWhenReady(page, '/LeaveRequests', '#leave-requests-content');

        await openNewLeaveRequestDialog(page);
        await setFlatpickrDate(page, '#startDate', '2026-03-21');
        await setFlatpickrDate(page, '#endDate', '2026-03-22');
        await page.fill('#notes', note);
        await page.getByRole('button', { name: 'Save' }).click();

        await expect(page.locator(`#${dialogOverlayMountDomId}`)).toBeEmpty();
        await expect(page.locator('#leave-requests-content')).toContainText(note);
        await expect(page.locator('#leave-requests-content article').filter({ hasText: note })).toHaveCount(1);
    });

    test('timesheet submit creates one card', async ({ page }) => {
        const startTime = '10:15';
        const endTime = '14:15';
        const note = `single-submit-timesheet-${Date.now()}`;

        await login(page);
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');

        await page.locator('[data-timesheet-day-add="true"]').first().click();
        await expect(page.locator('#timesheet-entry-create-form')).toBeVisible();
        await page.selectOption('#staffId', { label: 'E2E Manager' });
        await page.locator('input[name="startTime"]').evaluate((input, value) => {
            (input as HTMLInputElement).value = value as string;
        }, startTime);
        await page.locator('input[name="endTime"]').evaluate((input, value) => {
            (input as HTMLInputElement).value = value as string;
        }, endTime);
        await page.fill('textarea[name="staffComment"]', note);
        await page.getByRole('button', { name: 'Save' }).click();

        await expect(page.locator(`#${dialogOverlayMountDomId}`)).toBeEmpty();
        await expect(page.locator('[data-timesheet-operational-date]').first()).toContainText('10:15 AM');
        await expect(page.locator('[data-timesheet-operational-date]').first()).toContainText('2:15 PM');
        await expect(
            page.locator('[data-timesheet-operational-date]').first().locator(`.timesheet-entry-card:has-text("E2E Manager"):has-text("${note}")`)
        ).toHaveCount(1);
    });

    test('timesheet submit preserves the disabled Show approved preference', async ({ page }) => {
        resetTimesheetDisplayPreferences('e2e-test@example.com');
        const startTime = '10:30';
        const endTime = '14:30';
        const note = `show-approved-disabled-timesheet-${Date.now()}`;

        await login(page);
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');
        await openTimesheetSettings(page);
        const showApproved = page.locator('label', { hasText: 'Show approved' });
        if (await showApproved.locator('input[type="checkbox"]').isChecked()) {
            await showApproved.click();
        }
        await expect(page.locator('.timesheet-entry-card[data-timesheet-entry-approved="true"]')).toHaveCount(0);

        await page.locator('[data-timesheet-day-add="true"]').first().click();
        await expect(page.locator('#timesheet-entry-create-form')).toBeVisible();
        await page.selectOption('#staffId', { label: 'E2E Manager' });
        await page.locator('input[name="startTime"]').evaluate((input, value) => {
            (input as HTMLInputElement).value = value as string;
        }, startTime);
        await page.locator('input[name="endTime"]').evaluate((input, value) => {
            (input as HTMLInputElement).value = value as string;
        }, endTime);
        await page.fill('textarea[name="staffComment"]', note);
        await page.getByRole('button', { name: 'Save' }).click();

        await expect(page.locator(`#${dialogOverlayMountDomId}`)).toBeEmpty();
        await expect(page.locator('[data-timesheet-operational-date]').first()).toContainText('10:30 AM');
        await expect(page.locator('[data-timesheet-operational-date]').first()).toContainText('2:30 PM');
        await expect(page.locator('.timesheet-entry-card[data-timesheet-entry-approved="true"]')).toHaveCount(0);
        await expect(
            page.locator('[data-timesheet-operational-date]').first().locator(`.timesheet-entry-card:has-text("E2E Manager"):has-text("${note}")`)
        ).toHaveCount(1);
        resetTimesheetDisplayPreferences('e2e-test@example.com');
    });

    test('timesheet modal delete prompts for confirmation once', async ({ page }) => {
        const deletedEntryId = 'b1000000-0000-0000-0000-000000000091';
        runSql(`
            INSERT INTO timesheet_entries (
                id, venue_id, staff_id, shift_type_id, starts_at, ends_at, timezone, operational_date, is_approved,
                approved_at, approved_by_user_id, deleted_at, deleted_by_user_id, delete_reason
            )
            SELECT
                '${deletedEntryId}', venue_id, staff_id, shift_type_id,
                ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + TIME '17:00') AT TIME ZONE 'Australia/Melbourne',
                ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + TIME '18:00') AT TIME ZONE 'Australia/Melbourne',
                timezone, (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1))::date, FALSE, NULL, NULL, NULL, NULL, NULL
            FROM timesheet_entries
            WHERE id = 'a1000000-0000-0000-0000-000000000091'
            ON CONFLICT (id) DO UPDATE SET
                starts_at = EXCLUDED.starts_at,
                ends_at = EXCLUDED.ends_at,
                operational_date = EXCLUDED.operational_date,
                is_approved = FALSE,
                approved_at = NULL,
                approved_by_user_id = NULL,
                deleted_at = NULL,
                deleted_by_user_id = NULL,
                delete_reason = NULL,
                updated_at = NOW();
        `);
        resetTimesheetDisplayPreferences('e2e-test@example.com');

        await login(page);
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');
        await openTimesheetSettings(page);
        const showApproved = page.locator('label', { hasText: 'Show approved' });
        if (!(await showApproved.locator('input[type="checkbox"]').isChecked())) {
            await showApproved.click();
        }

        const targetEntry = page.locator(`.timesheet-entry-card:has(a[href*="${deletedEntryId}"])`);
        await expect(targetEntry).toBeVisible();
        const daySection = targetEntry.locator('xpath=ancestor::*[starts-with(@id, "timesheet-day-section-")]').first();
        const daySectionId = await daySection.getAttribute('id');
        expect(daySectionId).not.toBeNull();
        const updatedDaySection = page.locator(`#${daySectionId}`);

        const editLink = targetEntry.getByRole('link', { name: /Edit timesheet entry for/ });
        const editHref = await editLink.getAttribute('href');
        expect(editHref).not.toBeNull();
        expect(new URL(editHref!, page.url()).searchParams.get('timesheetEntryId')).toBe(deletedEntryId);

        await editLink.click();
        await expect(page.locator('#timesheet-entry-edit-form')).toBeVisible();

        await page.evaluate(() => {
            (window as Window & { __timesheetDeleteConfirmCalls?: number }).__timesheetDeleteConfirmCalls = 0;
            window.confirm = () => {
                (window as Window & { __timesheetDeleteConfirmCalls?: number }).__timesheetDeleteConfirmCalls =
                    ((window as Window & { __timesheetDeleteConfirmCalls?: number }).__timesheetDeleteConfirmCalls ?? 0) + 1;
                return true;
            };
        });

        const deleteResponsePromise = page.waitForResponse((response) =>
            response.request().method() === 'DELETE' && response.url().includes('/DeleteTimesheetEntry')
        );
        await page.getByRole('button', { name: 'Delete' }).click();
        const deleteResponse = await deleteResponsePromise;
        expect(deleteResponse.status(), await deleteResponse.text()).toBe(200);
        await deleteResponse.finished();

        await expect(page.locator(`#${dialogOverlayMountDomId}`)).toBeEmpty();
        await expect(updatedDaySection.locator(`.timesheet-entry-card a[href*="${deletedEntryId}"]`)).toHaveCount(0);
        await expect
            .poll(() => page.evaluate(() => (window as Window & { __timesheetDeleteConfirmCalls?: number }).__timesheetDeleteConfirmCalls ?? 0))
            .toBe(1);
        resetTimesheetDisplayPreferences('e2e-test@example.com');
    });
});
