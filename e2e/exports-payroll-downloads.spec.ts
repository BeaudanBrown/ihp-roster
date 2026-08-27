import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import {
    currentReportWeek,
    downloadExport,
    generatePayrollReport,
    gotoExports,
    loginAsPrivilegedUserWithSeededPasskeySession,
    payrollReportCard,
    shiftExportWeek,
    waitForExportJob,
    webauthnBaseURL,
} from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

test.describe('Payroll export downloads', () => {
    test.setTimeout(E2E_TIMEOUT.test);

    test('venue admin generates and redownloads one-week Payroll Workbook', async ({ page }) => {
        await loginAsPrivilegedUserWithSeededPasskeySession(page);
        await gotoExports(page);

        const workbookCard = payrollReportCard(page, 'Payroll Workbook');
        await expect(workbookCard).toHaveCount(1);
        await expect(workbookCard.getByRole('button', { name: 'Download workbook' })).toHaveCount(1);
        await expect(payrollReportCard(page, 'Payroll Earnings CSV')).toHaveCount(1);
        await expect(payrollReportCard(page, 'Approved Timesheets CSV')).toHaveCount(0);
        await expect(payrollReportCard(page, 'Staff Hours CSV')).toHaveCount(0);
        await expect(payrollReportCard(page, 'Hourly Breakdown ZIP')).toHaveCount(0);
        await expect(page.locator('[data-export-history="true"]').getByRole('heading', { name: 'Recent Exports' })).toBeVisible();
        await expect(page.locator('#admin-export-range-start')).toHaveCount(0);
        await expect(page.locator('#admin-export-range-end')).toHaveCount(0);

        const currentWeek = await currentReportWeek(page);
        await shiftExportWeek(page, 'Previous');
        const resetWeek = await shiftExportWeek(page, 'Current');
        expect(resetWeek).toEqual(currentWeek);

        const fileName = `payroll_workbook-${currentWeek.weekStart}-to-${currentWeek.weekEnd}.xlsx`;
        const generatedDownload = await generatePayrollReport(page, 'Payroll Workbook', 'Download workbook');
        expect(generatedDownload.suggestedFilename()).toBe(fileName);
        const historyRow = await waitForExportJob(page, fileName);
        await expect(historyRow).toContainText('Payroll Workbook');
        await expect(historyRow.getByRole('link', { name: 'Download workbook' })).toBeVisible();

        const historyDownload = await downloadExport(page, fileName, 'Download workbook');
        expect(historyDownload.suggestedFilename()).toBe(fileName);
    });
});
