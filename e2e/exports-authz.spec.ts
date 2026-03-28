import { test, expect } from '@playwright/test';
import { gotoExports, loginAs } from './test-helpers';

test.describe('Export authorization and negative cases', () => {
    test('manager only sees current-venue payroll reports and no management controls', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoExports(page);

        const payrollCards = page.locator('.border.rounded.p-2.bg-white');
        await expect(page.locator('body')).not.toContainText('Manage Report Definitions');
        await expect(payrollCards.filter({ hasText: 'Wage Report' })).toHaveCount(1);
        await expect(payrollCards.filter({ hasText: 'Staff Hours Report' })).toHaveCount(1);
        await expect(payrollCards.filter({ hasText: 'Kitchen Report' })).toHaveCount(1);
        await expect(payrollCards.filter({ hasText: 'Beta Hours' })).toHaveCount(0);
        await expect(page.locator('tbody tr')).toHaveCount(0);
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

        await loginAs(page, 'e2e-admin@example.com', 'test-password-123');
        await gotoExports(page);

        const createForm = page.locator('form').filter({
            has: page.getByText('Add Report Definition'),
        });

        await createForm.locator('input[name="slug"]').fill(duplicateSlug);
        await createForm.locator('input[name="name"]').fill(transientName);
        await createForm.locator('textarea[name="description"]').fill('Should fail');
        await createForm.locator('select[name="engine"]').selectOption('staff_pay_csv');
        await createForm.locator('input[name="sortOrder"]').fill('99');
        await createForm.locator('select[name="isActive"]').selectOption('true');
        await createForm.getByRole('button', { name: 'Add Report Definition' }).click();

        await expect(page.locator('body')).toContainText('That report slug is already in use for this venue.');
        await expect(page.locator('.border.rounded.p-2.bg-white').filter({ hasText: transientName })).toHaveCount(0);
        await expect(page.locator('form').filter({ has: page.locator(`input[name="slug"][value="${duplicateSlug}"]`) })).toHaveCount(1);
        await expect(page.locator('form').filter({ has: page.locator(`input[name="name"][value="${transientName}"]`) })).toHaveCount(0);
    });
});
