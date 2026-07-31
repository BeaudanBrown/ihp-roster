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
        await page.goto('/Admin#exports');
        await expect(page.getByRole('button', { name: 'Exports' })).toHaveCount(1);
        await gotoExports(page);

        await expect(payrollReportCard(page, 'Staff Hours CSV')).toHaveCount(1);
        await expect(payrollReportCard(page, 'Hourly Breakdown ZIP')).toHaveCount(1);
        await expect(payrollReportCard(page, 'Payroll Earnings CSV')).toHaveCount(1);
        await expect(page.locator('#report-definition-management')).toHaveCount(0);

        const currentWeek = await currentReportWeek(page);
        const rangeSuffix = `${currentWeek.weekStart}-to-${currentWeek.weekEnd}`;

        await generatePayrollReport(page, 'Staff Hours CSV');
        const staffHoursFileName = `staff_hrs_starting-${currentWeek.weekStart}.csv`;
        const staffHoursDownload = await downloadExport(page, staffHoursFileName);
        expect(staffHoursDownload.suggestedFilename()).toBe(staffHoursFileName);

        const staffHoursRows = parseCsv(await readDownloadText(staffHoursDownload));
        expect(staffHoursRows[0]).toEqual([
            'Employee',
            'Mon Ord',
            'Mon 7-12',
            'Mon 12+',
            'Tues Ord',
            'Tues 7-12',
            'Tues 12+',
            'Wed Ord',
            'Wed 7-12',
            'Wed 12+',
            'Thurs Ord',
            'Thurs 7-12',
            'Thurs 12+',
            'Fri Ord',
            'Fri 7-12',
            'Fri 12+',
            'Sat Ord',
            'Sat 12+',
            'Sun Ord',
        ]);
        expect(rowByNameType(staffHoursRows, 'Crew, Alpha Bar')).toEqual([
            'Crew, Alpha Bar',
            '8.00', '0.00', '0.00',
            '0.00', '0.00', '0.00',
            '0.00', '0.00', '0.00',
            '0.00', '0.00', '0.00',
            '0.00', '5.00', '0.00',
            '0.00', '1.00',
            '0.00',
        ]);
        expect(rowByNameType(staffHoursRows, 'Crew, Alpha Kitchen')).toEqual([
            'Crew, Alpha Kitchen',
            '0.00', '0.00', '0.00',
            '4.00', '0.00', '0.00',
            '0.00', '0.00', '0.00',
            '0.00', '0.00', '0.00',
            '0.00', '0.00', '0.00',
            '0.00', '0.00',
            '0.00',
        ]);

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
