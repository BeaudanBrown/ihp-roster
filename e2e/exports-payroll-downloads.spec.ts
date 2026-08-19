import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import {
    currentReportWeek,
    generatePayrollReport,
    gotoExports,
    loginAsPrivilegedUserWithSeededPasskeySession,
    payrollReportCard,
    parseCsv,
    readDownloadText,
    shiftExportWeek,
    webauthnBaseURL,
} from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

function rowByNameType(rows: string[][], nameType: string) {
    return rows.find((row) => row[0] === nameType);
}

test.describe('Payroll export downloads', () => {
    test.setTimeout(E2E_TIMEOUT.test);

    test('venue admin selects a roster week and immediately downloads Staff Hours CSV', async ({ page }) => {
        await loginAsPrivilegedUserWithSeededPasskeySession(page);
        await gotoExports(page);

        await expect(payrollReportCard(page, 'Staff Hours CSV')).toHaveCount(1);
        await expect(payrollReportCard(page, 'Approved Timesheets CSV')).toHaveCount(0);
        const hourlyBreakdownCard = payrollReportCard(page, 'Hourly Breakdown ZIP');
        await expect(hourlyBreakdownCard).toHaveCount(1);
        await expect(hourlyBreakdownCard.getByRole('button', { name: 'Download staff hours' })).toHaveCount(1);
        await expect(hourlyBreakdownCard.getByRole('button', { name: 'Download wage totals' })).toHaveCount(1);
        await expect(payrollReportCard(page, 'Payroll Earnings CSV')).toHaveCount(1);
        await expect(page.getByText('Recent Exports')).toHaveCount(0);
        await expect(page.locator('#admin-export-range-start')).toHaveCount(0);
        await expect(page.locator('#admin-export-range-end')).toHaveCount(0);

        const currentWeek = await currentReportWeek(page);
        await shiftExportWeek(page, 'Previous');
        const resetWeek = await shiftExportWeek(page, 'Current');
        expect(resetWeek).toEqual(currentWeek);

        const staffHoursDownload = await generatePayrollReport(page, 'Staff Hours CSV');
        const staffHoursFileName = `staff_hrs_starting-${currentWeek.weekStart}.csv`;
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
        expect(rowByNameType(staffHoursRows, 'Crew, Alpha LVL 1')).toEqual([
            'Crew, Alpha LVL 1',
            '8.000000', '0.000000', '0.000000',
            '4.000000', '0.000000', '0.000000',
            '0.000000', '0.000000', '0.000000',
            '0.000000', '0.000000', '0.000000',
            '0.000000', '5.000000', '0.000000',
            '0.000000', '1.000000',
            '0.000000',
        ]);
    });
});
