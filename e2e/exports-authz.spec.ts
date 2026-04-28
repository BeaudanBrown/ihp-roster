import { test, expect } from '@playwright/test';
import { gotoExports, loginAs, loginAsPrivilegedUserWithFreshPasskey, payrollReportCard, webauthnBaseURL } from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

test.describe('Export authorization and negative cases', () => {
    test('manager only sees current-venue payroll reports and no management controls', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoExports(page);

        await expect(page.locator('#report-definition-management')).toHaveCount(0);
        await expect(payrollReportCard(page, 'Wage Report')).toHaveCount(1);
        await expect(payrollReportCard(page, 'Staff Hours Report')).toHaveCount(1);
        await expect(payrollReportCard(page, 'Kitchen Report')).toHaveCount(1);
        await expect(payrollReportCard(page, 'Beta Hours')).toHaveCount(0);
        await expect(page.locator('#export-jobs-table tbody tr')).toHaveCount(0);
    });

    test('worker cannot access exports', async ({ page }) => {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await page.goto('/ExportJobs');

        await expect(page).toHaveTitle(/Access denied/i);
        await expect(page.locator('body')).toContainText('Error 403');
        await expect(page.locator('body')).toContainText('Access denied');
    });

    test('admin duplicate report-definition submission shows an error and does not mutate payroll actions', async ({ page }, testInfo) => {
        const duplicateSlug = 'wage';
        const transientName = `Duplicate Wage ${testInfo.retry}`;

        await loginAsPrivilegedUserWithFreshPasskey(page);
        await gotoExports(page);

        const createForm = page.locator('#report-definition-create-form');

        await createForm.locator('input[name="slug"]').fill(duplicateSlug);
        await createForm.locator('input[name="name"]').fill(transientName);
        await createForm.locator('textarea[name="description"]').fill('Should fail');
        await createForm.locator('select[name="engine"]').selectOption('staff_pay_csv');
        await createForm.locator('input[name="sortOrder"]').fill('99');
        await createForm.locator('select[name="isActive"]').selectOption('true');
        await createForm.getByRole('button', { name: 'Add Report Definition' }).click();

        await expect(page.locator('body')).toContainText('That report slug is already in use for this venue.');
        await expect(payrollReportCard(page, transientName)).toHaveCount(0);
        await expect(page.locator('[data-report-definition-editor="true"][data-report-definition-slug="wage"]')).toHaveCount(1);
        await expect(page.locator(`[data-report-definition-editor="true"] input[name="name"][value="${transientName}"]`)).toHaveCount(0);
    });
});
