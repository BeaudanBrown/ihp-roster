import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { gotoExports, loginAs, loginAsPrivilegedUserWithFreshPasskey, payrollReportCard, webauthnBaseURL } from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

test.describe('Export authorization and negative cases', () => {
    test.setTimeout(E2E_TIMEOUT.test);

    test('manager cannot access exports', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await page.goto('/ExportJobs');

        await expect(page).toHaveTitle(/Access denied/i);
        await expect(page.locator('body')).toContainText('Error 403');
        await expect(page.locator('body')).toContainText('Access denied');
    });

    test('worker cannot access exports', async ({ page }) => {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await page.goto('/ExportJobs');

        await expect(page).toHaveTitle(/Access denied/i);
        await expect(page.locator('body')).toContainText('Error 403');
        await expect(page.locator('body')).toContainText('Access denied');
    });

    test('venue admin sees the fixed export catalog without report-definition management', async ({ page }) => {
        await loginAsPrivilegedUserWithFreshPasskey(page);
        await gotoExports(page);

        await expect(page.locator('#report-definition-management')).toHaveCount(0);
        await expect(payrollReportCard(page, 'Approved Timesheets CSV')).toHaveCount(1);
        await expect(payrollReportCard(page, 'Staff Hours CSV')).toHaveCount(1);
        await expect(payrollReportCard(page, 'Hourly Breakdown ZIP')).toHaveCount(1);
        await expect(payrollReportCard(page, 'Payroll Earnings CSV')).toHaveCount(1);
    });
});
