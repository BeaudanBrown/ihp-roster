import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import {
    currentReportWeek,
    downloadExportAtIndex,
    generatePayrollReport,
    gotoExports,
    loginAsPrivilegedUserWithSeededPasskeySession,
    readDownloadText,
    readZipEntryText,
    listZipEntries,
    exportJobRows,
    webauthnBaseURL,
} from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

test.describe('Payroll export determinism', () => {
    test.setTimeout(E2E_TIMEOUT.test);

    test('repeated staff-hours generation preserves job history and identical CSV content', async ({ page }) => {
        await loginAsPrivilegedUserWithSeededPasskeySession(page);
        await page.goto('/Admin#exports');
        if ((await page.getByRole('button', { name: 'Exports' }).count()) === 0) {
            await expect(page.locator('[data-fixed-export-card="true"]')).toHaveCount(0);
            return;
        }
        await gotoExports(page);

        const { weekStart, weekEnd } = await currentReportWeek(page);
        const fileName = `staff_hours-${weekStart}-to-${weekEnd}.csv`;
        const initialCount = await exportJobRows(page, fileName).count();

        await generatePayrollReport(page, 'Staff Hours CSV');
        await generatePayrollReport(page, 'Staff Hours CSV');

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
        await loginAsPrivilegedUserWithSeededPasskeySession(page);
        await page.goto('/Admin#exports');
        if ((await page.getByRole('button', { name: 'Exports' }).count()) === 0) {
            await expect(page.locator('[data-fixed-export-card="true"]')).toHaveCount(0);
            return;
        }
        await gotoExports(page);

        const { weekStart, weekEnd } = await currentReportWeek(page);
        const fileName = `hourly_breakdown-${weekStart}-to-${weekEnd}.zip`;
        const initialCount = await exportJobRows(page, fileName).count();

        await generatePayrollReport(page, 'Hourly Breakdown ZIP');
        await generatePayrollReport(page, 'Hourly Breakdown ZIP');

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
