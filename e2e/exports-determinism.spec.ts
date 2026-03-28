import { test, expect } from '@playwright/test';
import {
    currentReportWeek,
    downloadExportAtIndex,
    generatePayrollReport,
    gotoExports,
    loginAs,
    readDownloadText,
    readZipEntryText,
    listZipEntries,
    exportJobRows,
} from './test-helpers';

test.describe('Payroll export determinism', () => {
    test('repeated staff-hours generation preserves job history and identical CSV content', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoExports(page);

        const { weekStart } = await currentReportWeek(page);
        const fileName = `staff_hours-${weekStart}.csv`;
        const initialCount = await exportJobRows(page, fileName).count();

        await generatePayrollReport(page, 'Staff Hours Report');
        await generatePayrollReport(page, 'Staff Hours Report');

        const rows = exportJobRows(page, fileName);
        await expect(rows).toHaveCount(initialCount + 2);
        await expect(rows.nth(initialCount)).toContainText('ready');
        await expect(rows.nth(initialCount + 1)).toContainText('ready');

        const firstDownload = await downloadExportAtIndex(page, fileName, initialCount);
        const secondDownload = await downloadExportAtIndex(page, fileName, initialCount + 1);

        const firstCsv = await readDownloadText(firstDownload);
        const secondCsv = await readDownloadText(secondDownload);

        expect(secondCsv).toBe(firstCsv);
    });

    test('repeated wage generation preserves job history and identical ZIP content', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoExports(page);

        const { weekStart } = await currentReportWeek(page);
        const fileName = `wage-${weekStart}.zip`;
        const initialCount = await exportJobRows(page, fileName).count();

        await generatePayrollReport(page, 'Wage Report');
        await generatePayrollReport(page, 'Wage Report');

        const rows = exportJobRows(page, fileName);
        await expect(rows).toHaveCount(initialCount + 2);
        await expect(rows.nth(initialCount)).toContainText('ready');
        await expect(rows.nth(initialCount + 1)).toContainText('ready');

        const firstDownload = await downloadExportAtIndex(page, fileName, initialCount);
        const secondDownload = await downloadExportAtIndex(page, fileName, initialCount + 1);

        const firstEntries = await listZipEntries(firstDownload);
        const secondEntries = await listZipEntries(secondDownload);
        expect(secondEntries).toEqual(firstEntries);

        for (const entryName of firstEntries) {
            const firstEntryText = await readZipEntryText(firstDownload, entryName);
            const secondEntryText = await readZipEntryText(secondDownload, entryName);
            expect(secondEntryText).toBe(firstEntryText);
        }
    });
});
