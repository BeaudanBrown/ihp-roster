import { test, expect } from '@playwright/test';
import { gotoExports, loginAs } from './test-helpers';

test.describe('Export report definition management', () => {
    test('venue admin can create and update report definitions and inactive ones disappear from payroll actions', async ({ page, browser }, testInfo) => {
        const createdSlug = `front-bar-${testInfo.retry}`;
        const updatedSlug = `front-house-${testInfo.retry}`;

        await loginAs(page, 'e2e-admin@example.com', 'test-password-123');
        await gotoExports(page);

        await expect(page.locator('body')).toContainText('Manage Report Definitions');
        await expect(page.locator('body')).toContainText('Wage Report');
        await expect(page.locator('body')).toContainText('Staff Hours Report');
        await expect(page.locator('body')).toContainText('Kitchen Report');

        const createForm = page.locator('form').filter({
            has: page.getByText('Add Report Definition'),
        });

        await createForm.locator('input[name="slug"]').fill(createdSlug);
        await createForm.locator('input[name="name"]').fill('Front Bar');
        await createForm.locator('textarea[name="description"]').fill('Front bar only');
        await createForm.locator('select[name="engine"]').selectOption('staff_pay_csv');
        await createForm.locator('input[name="sortOrder"]').fill('25');
        await createForm.locator('select[name="isActive"]').selectOption('true');
        await createForm.getByLabel('Bar').check();
        await createForm.getByRole('button', { name: 'Add Report Definition' }).click();

        const createdEditor = page.locator('form').filter({
            has: page.locator(`input[name="slug"][value="${createdSlug}"]`),
        });

        await expect(createdEditor).toHaveCount(1);
        await expect(createdEditor).toContainText('active');
        await expect(createdEditor).toContainText('Front Bar');
        await expect(createdEditor).toContainText(createdSlug);
        await expect(createdEditor).toContainText('Bar');
        await expect(
            page.locator('.border.rounded.p-2.bg-white').filter({ hasText: 'Front Bar' })
        ).toHaveCount(1);

        await createdEditor.locator('input[name="slug"]').fill(updatedSlug);
        await createdEditor.locator('input[name="name"]').fill('Front House');
        await createdEditor.locator('textarea[name="description"]').fill('');
        await createdEditor.locator('select[name="engine"]').selectOption('hourly_breakdown_zip');
        await createdEditor.locator('input[name="sortOrder"]').fill('5');
        await createdEditor.locator('select[name="isActive"]').selectOption('false');
        await createdEditor.getByLabel('Bar').uncheck();
        await createdEditor.getByLabel('Kitchen').check();
        await createdEditor.getByRole('button', { name: 'Update Report Definition' }).click();

        const updatedEditor = page.locator('form').filter({
            has: page.locator(`input[name="slug"][value="${updatedSlug}"]`),
        });
        await expect(updatedEditor).toHaveCount(1);
        await expect(updatedEditor).toContainText('inactive');
        await expect(updatedEditor).toContainText('Front House');
        await expect(updatedEditor).toContainText(updatedSlug);
        await expect(updatedEditor.locator('select[name="engine"]')).toHaveValue('hourly_breakdown_zip');
        await expect(updatedEditor.locator('select[name="isActive"]')).toHaveValue('false');
        await expect(updatedEditor.getByLabel('Kitchen')).toBeChecked();
        await expect(updatedEditor.getByLabel('Bar')).not.toBeChecked();

        const payrollCards = page.locator('.border.rounded.p-2.bg-white');
        await expect(payrollCards.filter({ hasText: 'Front House' })).toHaveCount(0);
        await expect(payrollCards.filter({ hasText: updatedSlug })).toHaveCount(0);

        const managerPage = await browser.newPage();
        await loginAs(managerPage, 'e2e-test@example.com', 'test-password-123');
        await gotoExports(managerPage);

        await expect(managerPage.locator('body')).not.toContainText('Manage Report Definitions');
        await expect(managerPage.locator('.border.rounded.p-2.bg-white').filter({ hasText: 'Front House' })).toHaveCount(0);
        await expect(managerPage.locator('.border.rounded.p-2.bg-white').filter({ hasText: updatedSlug })).toHaveCount(0);
        await managerPage.close();
    });
});
