import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import {
    currentReportWeek,
    generatePayrollReport,
    gotoExports,
    loginAsPrivilegedUserWithSeededPasskeySession,
    payrollReportCard,
    readZipEntryText,
    shiftExportWeek,
    webauthnBaseURL,
} from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

test.describe('Payroll export downloads', () => {
    test.setTimeout(E2E_TIMEOUT.test);

    test('venue admin generates the default and manages an ordered saved Payroll Workbook configuration', async ({ page }) => {
        await loginAsPrivilegedUserWithSeededPasskeySession(page);
        await gotoExports(page);

        const workbookCard = payrollReportCard(page, 'Payroll Workbook');
        await expect(workbookCard).toHaveCount(1);
        await expect(workbookCard.getByRole('button', { name: 'Download workbook' })).toHaveCount(1);
        await expect(payrollReportCard(page, 'Payroll Earnings CSV')).toHaveCount(1);
        await expect(payrollReportCard(page, 'Approved Timesheets CSV')).toHaveCount(0);
        await expect(payrollReportCard(page, 'Staff Hours CSV')).toHaveCount(0);
        await expect(payrollReportCard(page, 'Hourly Breakdown ZIP')).toHaveCount(0);
        await expect(page.locator('[data-export-history="true"]')).toHaveCount(0);
        await expect(page.locator('#admin-export-range-start')).toHaveCount(0);
        await expect(page.locator('#admin-export-range-end')).toHaveCount(0);

        const currentWeek = await currentReportWeek(page);
        await shiftExportWeek(page, 'Previous');
        const resetWeek = await shiftExportWeek(page, 'Current');
        expect(resetWeek).toEqual(currentWeek);

        const fileName = `payroll_workbook-${currentWeek.weekStart}-to-${currentWeek.weekEnd}.xlsx`;

        await page.locator('#payroll-workbook-configuration-name').fill('Wages then Summary');
        await page.locator('#payroll-workbook-family-1').selectOption('shift-type-wages');
        await page.locator('#payroll-workbook-family-2').selectOption('summary');
        await page.getByRole('button', { name: 'Save configuration' }).click();

        const configurationRow = page.locator('[data-payroll-workbook-configuration]').filter({ hasText: 'Wages then Summary' });
        await expect(configurationRow).toHaveCount(1, { timeout: E2E_TIMEOUT.assertion });
        await expect(configurationRow).toContainText('Shift Type Wages → Summary');

        const configuredRefresh = page.waitForResponse((response) => response.url().includes('/ShowadminExportsLiveFragment'), { timeout: E2E_TIMEOUT.assertion });
        const configuredDownload = await generatePayrollReport(page, 'Wages then Summary', 'Download workbook');
        expect(configuredDownload.suggestedFilename()).toBe(fileName);
        await configuredRefresh;
        const workbookXml = await readZipEntryText(configuredDownload, 'xl/workbook.xml');
        expect(workbookXml).toContain('Shift Type Wages Mon');
        expect(workbookXml).toContain('Summary ');
        expect(workbookXml).not.toContain('Hours Mon');
        expect(workbookXml).toContain('name="Data"');

        await gotoExports(page);
        await expect(configurationRow).toHaveCount(1, { timeout: E2E_TIMEOUT.assertion });
        await configurationRow.getByText('Delete', { exact: true }).click();
        await configurationRow.getByRole('button', { name: 'Confirm delete Wages then Summary' }).click();
        await expect(configurationRow).toHaveCount(0, { timeout: E2E_TIMEOUT.assertion });
        await expect(payrollReportCard(page, 'Payroll Workbook')).toHaveCount(1);

        const generatedDownload = await generatePayrollReport(page, 'Payroll Workbook', 'Download workbook');
        expect(generatedDownload.suggestedFilename()).toBe(fileName);
    });
});
