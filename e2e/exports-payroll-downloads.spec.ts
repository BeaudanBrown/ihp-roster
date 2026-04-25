import { test, expect } from '@playwright/test';
import {
    currentReportWeek,
    downloadExport,
    generatePayrollReport,
    gotoExports,
    loginAs,
    payrollReportCard,
    parseCsv,
    readDownloadText,
    readZipEntryText,
    shiftExportWeek,
    listZipEntries,
} from './test-helpers';

function rowByNameType(rows: string[][], nameType: string) {
    return rows.find((row) => row[0] === nameType);
}

function rowByHour(rows: string[][], hour: string) {
    return rows.find((row) => row[0] === hour);
}

test.describe('Payroll export downloads', () => {
    test('manager can generate and download staff_hours, kitchen, and wage exports', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoExports(page);

        await expect(payrollReportCard(page, 'Staff Hours Report')).toHaveCount(1);
        await expect(payrollReportCard(page, 'Kitchen Report')).toHaveCount(1);
        await expect(payrollReportCard(page, 'Wage Report')).toHaveCount(1);
        await expect(page.locator('#report-definition-management')).toHaveCount(0);

        const currentWeek = await currentReportWeek(page);
        await shiftExportWeek(page, 'Previous');
        const previousWeek = await currentReportWeek(page);
        expect(previousWeek.weekStart).not.toBe(currentWeek.weekStart);
        await shiftExportWeek(page, 'Current');
        await expect.poll(async () => (await currentReportWeek(page)).weekStart).toBe(currentWeek.weekStart);

        await generatePayrollReport(page, 'Staff Hours Report');
        const staffHoursDownload = await downloadExport(page, `staff_hours-${currentWeek.weekStart}.csv`);
        expect(staffHoursDownload.suggestedFilename()).toBe(`staff_hours-${currentWeek.weekStart}.csv`);

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

        await generatePayrollReport(page, 'Kitchen Report');
        const kitchenDownload = await downloadExport(page, `kitchen-${currentWeek.weekStart}.csv`);
        expect(kitchenDownload.suggestedFilename()).toBe(`kitchen-${currentWeek.weekStart}.csv`);

        const kitchenRows = parseCsv(await readDownloadText(kitchenDownload));
        expect(kitchenRows[0]).toEqual(staffHoursRows[0]);
        expect(rowByNameType(kitchenRows, 'Alpha')).toEqual([
            'Alpha',
            '0.00', '0.00', '0.00',
            '4.00', '0.00', '0.00',
            '0.00', '0.00', '0.00',
            '0.00', '0.00', '0.00',
            '0.00', '0.00', '0.00',
            '0.00', '0.00',
            '0.00',
        ]);

        await generatePayrollReport(page, 'Wage Report');
        const wageDownload = await downloadExport(page, `wage-${currentWeek.weekStart}.zip`);
        expect(wageDownload.suggestedFilename()).toBe(`wage-${currentWeek.weekStart}.zip`);

        const zipEntries = await listZipEntries(wageDownload);
        expect(zipEntries).toEqual([
            'Monday.csv',
            'Tuesday.csv',
            'Wednesday.csv',
            'Thursday.csv',
            'Friday.csv',
            'Saturday.csv',
            'Sunday.csv',
        ]);

        const mondayRows = parseCsv(await readZipEntryText(wageDownload, 'Monday.csv'));
        expect(mondayRows[0]).toEqual(['Time', 'Bar', 'Kitchen', 'Floor']);
        expect(rowByHour(mondayRows, '08:00')).toEqual(['08:00', '1.0', '', '']);
        expect(rowByHour(mondayRows, '09:00')).toEqual(['09:00', '1.0', '', '1.0']);
        expect(rowByHour(mondayRows, '10:00')).toEqual(['10:00', '1.0', '', '1.0']);
    });
});
