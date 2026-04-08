import { test, expect } from '@playwright/test';
import { gotoWhenReady } from './test-helpers';

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
    test('leave request modal date fields get flatpickr after HTMX swap', async ({ page }) => {
        await login(page);
        await gotoWhenReady(page, '/LeaveRequests', '#leave-requests-content');

        await page.getByRole('link', { name: 'New Request' }).click();
        await expect(page.locator('#leave-request-form')).toBeVisible();

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

        await page.getByRole('link', { name: 'New Request' }).click();
        await expect(page.locator('#leave-request-form')).toBeVisible();
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
});
