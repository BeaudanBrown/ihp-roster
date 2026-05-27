import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import {
    currentReportWeek,
    downloadExport,
    generatePayrollReport,
    gotoExports,
    loginAsPrivilegedUserWithSeededPasskeySession,
    payrollReportCard,
    parseCsv,
    readDownloadText,
    readZipEntryText,
    listZipEntries,
    webauthnBaseURL,
} from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

function rowByNameType(rows: string[][], nameType: string) {
    return rows.find((row) => row[0] === nameType);
}

function rowByHour(rows: string[][], hour: string) {
    return rows.find((row) => row[0] === hour);
}

test.describe('Payroll export downloads', () => {
    test.setTimeout(E2E_TIMEOUT.test);

    test('venue admin can generate and download staff_hours and hourly breakdown exports', async ({ page }) => {
        await loginAsPrivilegedUserWithSeededPasskeySession(page);
        await gotoExports(page);

        await expect(payrollReportCard(page, 'Staff Hours CSV')).toHaveCount(1);
        await expect(payrollReportCard(page, 'Hourly Breakdown ZIP')).toHaveCount(1);
        await expect(payrollReportCard(page, 'Payroll Earnings CSV')).toHaveCount(1);
        await expect(page.locator('#report-definition-management')).toHaveCount(0);

        const currentWeek = await currentReportWeek(page);
        const rangeSuffix = `${currentWeek.weekStart}-to-${currentWeek.weekEnd}`;

        await generatePayrollReport(page, 'Staff Hours CSV');
        const staffHoursDownload = await downloadExport(page, `staff_hours-${rangeSuffix}.csv`);
        expect(staffHoursDownload.suggestedFilename()).toBe(`staff_hours-${rangeSuffix}.csv`);

        const staffHoursRows = parseCsv(await readDownloadText(staffHoursDownload));
        expect(staffHoursRows[0]).toEqual([
            'Name/Type',
            'Mond Ord',
            'Mond 7-12',
            'Mond 12+',
            'Tues Ord',
            'Tues 7-12',
            'Tues 12+',
            'Wedn Ord',
            'Wedn 7-12',
            'Wedn 12+',
            'Thur Ord',
            'Thur 7-12',
            'Thur 12+',
            'Frid Ord',
            'Frid 7-12',
            'Frid 12+',
            'Satu Ord',
            'Satu 12+',
            'Sund Ord',
        ]);
        expect(rowByNameType(staffHoursRows, 'Alpha LVL 1')).toEqual([
            'Alpha LVL 1',
            '8.00', '0.00', '0.00',
            '4.00', '0.00', '0.00',
            '0.00', '0.00', '0.00',
            '0.00', '0.00', '0.00',
            '0.00', '5.00', '0.00',
            '0.00', '1.00',
            '0.00',
        ]);
        expect(rowByNameType(staffHoursRows, 'Alpha LVL 2')).toBeUndefined();

        await generatePayrollReport(page, 'Hourly Breakdown ZIP');
        const wageDownload = await downloadExport(page, `hourly_breakdown-${rangeSuffix}.zip`);
        expect(wageDownload.suggestedFilename()).toBe(`hourly_breakdown-${rangeSuffix}.zip`);

        const zipEntries = await listZipEntries(wageDownload);
        expect(zipEntries).toContain(`${currentWeek.weekStart}_Monday.csv`);

        const mondayRows = parseCsv(await readZipEntryText(wageDownload, `${currentWeek.weekStart}_Monday.csv`));
        expect(mondayRows[0]).toEqual(['Time', 'Bar', 'Kitchen', 'Floor']);
        expect(rowByHour(mondayRows, '08:00')).toEqual(['08:00', '1.0', '', '']);
        expect(rowByHour(mondayRows, '09:00')).toEqual(['09:00', '1.0', '', '1.0']);
        expect(rowByHour(mondayRows, '10:00')).toEqual(['10:00', '1.0', '', '1.0']);
    });
});
