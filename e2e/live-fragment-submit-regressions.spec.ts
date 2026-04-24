import { test, expect } from '@playwright/test';
import { writeFile } from 'node:fs/promises';
import { gotoWhenReady, loginAs, openNewLeaveRequestDialog } from './test-helpers';

async function login(page) {
    await gotoWhenReady(page, '/NewSession', '#email');
    await page.fill('#email', 'e2e-test@example.com');
    await page.fill('#password', 'test-password-123');
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/, { timeout: 60000 });
    await expect(page.locator('#roster-week-shell')).toBeVisible();
}

async function setFlatpickrDate(page, selector: string, value: string) {
    await page.locator(selector).evaluate((input, nextValue) => {
        const flatpickr = (input as HTMLInputElement & {
            _flatpickr?: { setDate: (date: string, triggerChange?: boolean) => void };
        })._flatpickr;

        if (!flatpickr) {
            throw new Error(`No flatpickr instance on ${selector}`);
        }

        flatpickr.setDate(nextValue as string, true);
    }, value);
}

test.describe('HTMX submit regressions', () => {
    test('profile leave submit appends a leave request without nesting the whole profile page', async ({ page }) => {
        const note = 'profile-leave-submit-check';

        await loginAs(page, 'e2e-admin@example.com', 'test-password-123');
        await gotoWhenReady(page, '/EditProfile', '#profile-content-fragment');

        const leaveSectionToggle = page.getByRole('button', { name: 'Leave Requests' });
        if ((await leaveSectionToggle.getAttribute('aria-expanded')) !== 'true') {
            await leaveSectionToggle.click();
        }

        await expect(page.locator('#profile-leave-request-form-fragment')).toBeVisible();
        await expect(page.locator('#profile-leave-requests-list-fragment')).toBeVisible();

        const initialCount = await page.locator('#profile-leave-requests-list-fragment .leave-request-row').count();
        const submitResponsePromise = page.waitForResponse((response) =>
            response.request().method() === 'POST' && response.url().includes('/CreateLeaveRequest')
        );

        await setFlatpickrDate(page, '#startDate', '2026-03-23');
        await setFlatpickrDate(page, '#endDate', '2026-03-24');
        await page.fill('#notes', note);
        await page.getByRole('button', { name: 'Submit Leave Request' }).click();

        const submitResponse = await submitResponsePromise;
        const submitResponseText = await submitResponse.text();
        await writeFile(test.info().outputPath('profile-leave-submit-response.html'), submitResponseText);

        await expect(page.locator('#profile-leave-request-form-fragment')).toBeVisible();
        await expect(page.locator('#profile-leave-requests-list-fragment')).toContainText(note);
        await expect(page.locator('#profile-leave-requests-list-fragment .leave-request-row')).toHaveCount(initialCount + 1);
        await expect(page.locator('#profile-leave-request-form-fragment #profile-content-fragment')).toHaveCount(0);
        await expect(page.locator('#profile-leave-request-form-fragment #profile-leave-requests-content')).toHaveCount(0);
        expect(submitResponseText).not.toContain('id="profile-content-fragment"');
        expect(submitResponseText).not.toContain('id="profile-leave-requests-content"');
    });

    test('leave request modal date fields get flatpickr after HTMX swap', async ({ page }) => {
        await login(page);
        await gotoWhenReady(page, '/LeaveRequests', '#leave-requests-content');

        await openNewLeaveRequestDialog(page);

        await expect(page.locator('#startDate.flatpickr-input')).toBeVisible();
        await expect(page.locator('#endDate.flatpickr-input')).toBeVisible();
        await expect.poll(async () => {
            return page.locator('#startDate').evaluate((input) => Boolean((input as HTMLInputElement & { _flatpickr?: unknown })._flatpickr));
        }).toBe(true);
        await expect.poll(async () => {
            return page.locator('#endDate').evaluate((input) => Boolean((input as HTMLInputElement & { _flatpickr?: unknown })._flatpickr));
        }).toBe(true);
    });

    test('leave request submit creates one request', async ({ page }) => {
        const note = 'single-submit-leave-check';

        await login(page);
        await gotoWhenReady(page, '/LeaveRequests', '#leave-requests-content');

        await openNewLeaveRequestDialog(page);
        await setFlatpickrDate(page, '#startDate', '2026-03-21');
        await setFlatpickrDate(page, '#endDate', '2026-03-22');
        await page.fill('#notes', note);
        await page.getByRole('button', { name: 'Save' }).click();

        await expect(page.locator('#dialog-overlay-mount')).toBeEmpty();
        await expect(page.locator('#leave-requests-content')).toContainText(note);
        await expect(page.locator('#leave-requests-content article').filter({ hasText: note })).toHaveCount(1);
    });

    test('timesheet submit creates one card', async ({ page }) => {
        const startTime = '10:15';
        const endTime = '14:15';
        const renderedRange = '10:15 AM - 2:15 PM';

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
        await page.getByRole('button', { name: 'Save' }).click();

        await expect(page.locator('#dialog-overlay-mount')).toBeEmpty();
        await expect(page.locator('#timesheet-day-section-0')).toContainText(renderedRange);
        await expect(
            page.locator(`#timesheet-day-section-0 .timesheet-entry-card:has-text("E2E Manager"):has-text("${renderedRange}")`)
        ).toHaveCount(1);
    });

    test('timesheet modal delete prompts for confirmation once', async ({ page }) => {
        await login(page);
        await gotoWhenReady(page, '/Timesheets?showApproved=true&showAllStaff=true', '#timesheet-week-shell');

        const approvedEntry = page.locator('.timesheet-entry-card[data-timesheet-entry-approved="true"]').first();
        await expect(approvedEntry).toBeVisible();

        const initialApprovedCount = await page.locator('.timesheet-entry-card[data-timesheet-entry-approved="true"]').count();
        await approvedEntry.getByRole('link', { name: 'Edit' }).click();
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
        await deleteResponsePromise;

        await expect(page.locator('#dialog-overlay-mount')).toBeEmpty();
        await expect(page.locator('.timesheet-entry-card[data-timesheet-entry-approved="true"]')).toHaveCount(initialApprovedCount - 1);
        await expect
            .poll(() => page.evaluate(() => (window as Window & { __timesheetDeleteConfirmCalls?: number }).__timesheetDeleteConfirmCalls ?? 0))
            .toBe(1);
    });
});
