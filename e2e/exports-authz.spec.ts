import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { gotoExports, payrollReportCard } from './support/exports';
import { loginAs } from './support/session';
import { loginAsPrivilegedUserWithSeededPasskeySession, webauthnBaseURL } from './support/passkeys';

test.use({ baseURL: webauthnBaseURL });

test.describe('Export authorization and negative cases', () => {
    test.setTimeout(E2E_TIMEOUT.test);

    test('manager cannot access exports', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await page.goto('/Admin');

        await expect(page.locator('#roster-week-shell')).toBeVisible();
        await expect(page.getByRole('link', { name: 'admin' })).toHaveCount(0);
        await expect(page.getByRole('button', { name: 'Exports' })).toHaveCount(0);
        await expect(page.locator('[data-fixed-export-card="true"]')).toHaveCount(0);
    });

    test('worker cannot access exports', async ({ page }) => {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await page.goto('/Admin');

        await expect(page.locator('#roster-week-shell')).toBeVisible();
        await expect(page.getByRole('link', { name: 'admin' })).toHaveCount(0);
        await expect(page.getByRole('button', { name: 'Exports' })).toHaveCount(0);
        await expect(page.locator('[data-fixed-export-card="true"]')).toHaveCount(0);
    });

    test('venue admin sees the unified Payroll Workbook export list', async ({ page }) => {
        await loginAsPrivilegedUserWithSeededPasskeySession(page);
        await gotoExports(page);

        await expect(page.locator('#payroll-workbook-configuration-management')).toHaveCount(0);
        await expect(page.getByRole('button', { name: 'Create new export' })).toBeVisible();
        await expect(page.getByRole('button', { name: 'Exports' })).toBeVisible();
        await expect(payrollReportCard(page, 'Approved Timesheets CSV')).toHaveCount(0);
        await expect(payrollReportCard(page, 'Payroll Workbook')).toHaveCount(1);
        await expect(payrollReportCard(page, 'Payroll Earnings CSV')).toHaveCount(0);
        await expect(payrollReportCard(page, 'Staff Hours CSV')).toHaveCount(0);
        await expect(payrollReportCard(page, 'Hourly Breakdown ZIP')).toHaveCount(0);
    });
});
