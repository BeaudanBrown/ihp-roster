import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { checkboxListItemDomAttr, checkboxListGroupToggleDomAttr } from '../frontend/ts/generated/contracts';
import {
    currentReportWeek,
    generatePayrollReport,
    gotoExports,
    payrollReportCard,
    readZipEntryText,
    shiftExportWeek,
} from './support/exports';
import { loginAsPrivilegedUserWithSeededPasskeySession, webauthnBaseURL } from './support/passkeys';
import { runSql } from './support/database';

test.use({ baseURL: webauthnBaseURL });

test.describe('Payroll export downloads', () => {
    test.setTimeout(E2E_TIMEOUT.test);

    test('venue admin creates, edits, generates, and deletes ordered Payroll Workbook exports', async ({ page }, testInfo) => {
        test.setTimeout(E2E_TIMEOUT.payrollWorkflowTest);
        runSql(`
            DELETE FROM payroll_workbook_configurations
            WHERE name IN ('Wages then Summary', 'Hours then Wages');
            INSERT INTO payroll_workbook_configurations
                (id, venue_id, name, definition_version, revision, created_by_user_id, created_at, updated_at)
            VALUES
                ('a1000000-0000-0000-0000-000000000801', 'a1000000-0000-0000-0000-000000000001',
                 'Payroll Workbook', 1, 0, 'a0000000-0000-0000-0000-000000000003', NOW(), NOW())
            ON CONFLICT (id) DO UPDATE SET
                venue_id = EXCLUDED.venue_id,
                name = EXCLUDED.name,
                definition_version = EXCLUDED.definition_version,
                revision = EXCLUDED.revision,
                created_by_user_id = EXCLUDED.created_by_user_id,
                updated_at = NOW();
            DELETE FROM payroll_workbook_configuration_families
            WHERE configuration_id = 'a1000000-0000-0000-0000-000000000801';
            INSERT INTO payroll_workbook_configuration_families (id, configuration_id, family_key, position)
            VALUES
                ('a1000000-0000-0000-0000-000000000811', 'a1000000-0000-0000-0000-000000000801', 'summary', 0),
                ('a1000000-0000-0000-0000-000000000812', 'a1000000-0000-0000-0000-000000000801', 'employee-pay-bucket-hours', 1),
                ('a1000000-0000-0000-0000-000000000813', 'a1000000-0000-0000-0000-000000000801', 'shift-type-hours', 2),
                ('a1000000-0000-0000-0000-000000000814', 'a1000000-0000-0000-0000-000000000801', 'employee-pay-bucket-wages', 3),
                ('a1000000-0000-0000-0000-000000000815', 'a1000000-0000-0000-0000-000000000801', 'shift-type-wages', 4);
        `);
        await loginAsPrivilegedUserWithSeededPasskeySession(page);
        await gotoExports(page);

        const standardCard = payrollReportCard(page, 'Payroll Workbook');
        await expect(standardCard).toHaveCount(1);
        await expect(standardCard).toContainText('Sheets: Summary → Hours by Staff → Hours by Shift Type → Wages by Staff → Wages by Shift Type');
        await expect(page.getByText('Each export uses its sheet families in the order shown.')).toHaveCount(0);
        await expect(page.getByText('Download a configured Payroll Workbook for the selected roster week.')).toHaveCount(0);
        await expect(standardCard.getByRole('button', { name: 'Download', exact: true })).toHaveCount(1);
        await expect(standardCard.getByRole('button', { name: 'Edit' })).toHaveCount(1);
        await expect(standardCard.getByRole('button', { name: 'Delete' })).toHaveCount(1);
        await expect(payrollReportCard(page, 'Payroll Earnings CSV')).toHaveCount(0);
        await expect(payrollReportCard(page, 'Approved Timesheets CSV')).toHaveCount(0);
        await expect(page.locator('[data-export-history="true"]')).toHaveCount(0);

        const currentWeek = await currentReportWeek(page);
        await shiftExportWeek(page, 'Previous');
        const resetWeek = await shiftExportWeek(page, 'Current');
        expect(resetWeek).toEqual(currentWeek);
        const fileName = `payroll-workbook-${currentWeek.weekStart}-to-${currentWeek.weekEnd}.xlsx`;

        const standardDownload = await generatePayrollReport(page, 'Payroll Workbook', 'Download');
        expect(standardDownload.suggestedFilename()).toBe(fileName);

        await gotoExports(page);
        await standardCard.getByRole('button', { name: 'Filtered…' }).click();
        const selectionDialog = page.getByRole('dialog', { name: 'Choose shifts for export' });
        await expect(selectionDialog).toBeVisible();
        await expect(selectionDialog).not.toContainText('Review this selection');
        await expect(selectionDialog.locator('legend').first()).toHaveText(/^[A-Za-z]+ \d{2}\/\d{2}$/);
        const selectedDownload = selectionDialog.getByRole('button', { name: 'Download', exact: true });
        await expect(selectedDownload).toHaveAttribute('form', 'timesheet-selection-form');
        await expect(selectedDownload).toHaveAttribute('type', 'submit');
        await expect(selectedDownload).not.toHaveAttribute('hx-post');
        await expect(selectionDialog.locator('form').getByRole('button', { name: 'Download', exact: true })).toHaveCount(0);
        const shifts = selectionDialog.locator(`[${checkboxListItemDomAttr}]`);
        const firstDay = selectionDialog.locator('fieldset').first();
        const dayCheckbox = firstDay.locator(`[${checkboxListGroupToggleDomAttr}]`);
        const firstDayShifts = firstDay.locator(`[${checkboxListItemDomAttr}]`);
        const selectionRequests: string[] = [];
        const recordSelectionRequest = (request: import('@playwright/test').Request) => {
            if (request.method() === 'POST') selectionRequests.push(request.url());
        };
        page.on('request', recordSelectionRequest);
        expect(await shifts.count()).toBeGreaterThan(0);
        await selectionDialog.getByRole('button', { name: 'Clear all', exact: true }).click();
        await expect(selectionDialog.getByRole('status')).toContainText('0 shifts selected');
        await expect(selectedDownload).toBeDisabled();
        await shifts.first().locator('..').click();
        await expect(selectionDialog.getByRole('status')).toContainText('1 shifts selected');
        await expect(selectedDownload).toBeEnabled();
        expect(await firstDayShifts.count()).toBeGreaterThan(1);
        await expect(dayCheckbox).not.toBeChecked();
        for (const shift of await firstDayShifts.all()) await shift.check();
        await expect(dayCheckbox).toBeChecked();
        await firstDay.locator('legend label').click();
        await expect(firstDay.locator(`[${checkboxListItemDomAttr}]:checked`)).toHaveCount(0);
        await expect(dayCheckbox).not.toBeChecked();
        await firstDay.locator('legend label').click();
        await expect(dayCheckbox).toBeChecked();
        await expect(firstDay.locator('input:not(:checked)')).toHaveCount(0);
        await selectionDialog.getByRole('button', { name: 'Select all', exact: true }).click();
        expect(selectionRequests).toEqual([]);
        page.off('request', recordSelectionRequest);
        await page.screenshot({ path: testInfo.outputPath('selection-checklist.png') });
        await expect(selectionDialog.locator('input[type="checkbox"]:not(:checked)')).toHaveCount(0);
        const filteredDownloadEvent = page.waitForEvent('download');
        await selectedDownload.click();
        const filteredDownload = await filteredDownloadEvent;
        expect(filteredDownload.suggestedFilename()).toBe(fileName);
        await expect(selectionDialog).toHaveCount(0);
        expect(await readZipEntryText(filteredDownload, 'xl/worksheets/sheet1.xml'))
            .toEqual(await readZipEntryText(standardDownload, 'xl/worksheets/sheet1.xml'));

        await gotoExports(page);
        await page.getByRole('button', { name: 'Create new export' }).click();
        const addDialog = page.getByRole('dialog', { name: 'Add export' });
        await expect(addDialog).toBeVisible();
        await expect(addDialog.getByText('No sheets included.')).toBeVisible();
        await expect(addDialog.getByRole('heading', { name: 'Excluded sheets' })).toBeVisible();
        await expect(addDialog.locator('#payroll-workbook-configuration-name')).toHaveValue('');
        await addDialog.locator('#payroll-workbook-configuration-name').fill('Empty export');
        await addDialog.getByRole('button', { name: 'Save' }).click();
        await expect(addDialog.getByRole('alert')).toContainText('at least one presentation sheet family');

        await addDialog.locator('#payroll-workbook-configuration-name').fill('Wages then Summary');
        await addDialog.getByRole('button', { name: 'Add Summary' }).click();
        await addDialog.getByRole('button', { name: 'Add Wages by Shift Type' }).click();
        await addDialog.getByRole('button', { name: 'Move Wages by Shift Type up' }).click();
        const createSaveResponse = page.waitForResponse((response) =>
            response.request().method() === 'POST' && response.url().includes('/CreatePayrollWorkbookConfiguration')
        );
        await addDialog.getByRole('button', { name: 'Save' }).click();
        expect((await createSaveResponse).ok()).toBe(true);
        await page.reload();
        await gotoExports(page);

        const configurationRow = page.locator('[data-payroll-workbook-configuration]').filter({ hasText: 'Wages then Summary' });
        await expect(configurationRow).toHaveCount(1, { timeout: E2E_TIMEOUT.assertion });
        await expect(configurationRow).toContainText('Sheets: Wages by Shift Type → Summary');

        const configuredRefresh = page.waitForResponse((response) => response.url().includes('/ShowadminExportsLiveFragment'), { timeout: E2E_TIMEOUT.assertion });
        const configuredDownload = await generatePayrollReport(page, 'Wages then Summary', 'Download');
        expect(configuredDownload.suggestedFilename()).toBe(`wages-then-summary-${currentWeek.weekStart}-to-${currentWeek.weekEnd}.xlsx`);
        await configuredRefresh;
        const workbookXml = await readZipEntryText(configuredDownload, 'xl/workbook.xml');
        expect(workbookXml).toContain('Shift Type Wages Mon');
        expect(workbookXml).toContain('Summary ');
        expect(workbookXml).not.toContain('Hours Mon');
        expect(workbookXml).toContain('name="Data"');

        await gotoExports(page);
        await configurationRow.getByRole('button', { name: 'Edit' }).click();
        const editDialog = page.getByRole('dialog', { name: 'Edit export' });
        await expect(editDialog).toBeVisible();
        await editDialog.locator('#payroll-workbook-configuration-name').fill('Hours then Wages');
        await editDialog.getByRole('button', { name: 'Remove Summary' }).click();
        await editDialog.getByRole('button', { name: 'Add Hours by Staff' }).click();
        await editDialog.getByRole('button', { name: 'Move Hours by Staff up' }).click();
        const editSaveResponse = page.waitForResponse((response) =>
            response.request().method() === 'POST' && response.url().includes('/UpdatePayrollWorkbookConfiguration')
        );
        await editDialog.getByRole('button', { name: 'Save' }).click();
        expect((await editSaveResponse).ok()).toBe(true);
        await page.reload();
        await gotoExports(page);

        const editedRow = page.locator('[data-payroll-workbook-configuration]').filter({ hasText: 'Hours then Wages' });
        await expect(editedRow).toHaveCount(1, { timeout: E2E_TIMEOUT.assertion });
        await expect(editedRow).toContainText('Sheets: Hours by Staff → Wages by Shift Type');
        await expect(configurationRow).toHaveCount(0);

        await editedRow.getByRole('button', { name: 'Delete' }).click();
        const deleteEditedDialog = page.getByRole('dialog', { name: 'Delete export' });
        await expect(deleteEditedDialog).toContainText('Hours then Wages');
        const deleteEditedForm = deleteEditedDialog.locator('form');
        await expect(deleteEditedForm).toHaveCount(1);
        await expect(deleteEditedForm).toHaveAttribute('action', /DeletePayrollWorkbookConfiguration/);
        const editedDeleteResponse = page.waitForResponse((response) =>
            response.request().method() === 'DELETE' && response.url().includes('/DeletePayrollWorkbookConfiguration')
        );
        await deleteEditedDialog.getByRole('button', { name: 'Delete' }).click();
        expect((await editedDeleteResponse).ok()).toBe(true);
        await expect(editedRow).toHaveCount(0, { timeout: E2E_TIMEOUT.assertion });

        const refreshedStandardCard = payrollReportCard(page, 'Payroll Workbook');
        await refreshedStandardCard.getByRole('button', { name: 'Delete' }).click();
        const deleteStandardDialog = page.getByRole('dialog', { name: 'Delete export' });
        await expect(deleteStandardDialog).toContainText('Payroll Workbook');
        const standardDeleteResponse = page.waitForResponse((response) =>
            response.request().method() === 'DELETE' && response.url().includes('/DeletePayrollWorkbookConfiguration')
        );
        await deleteStandardDialog.getByRole('button', { name: 'Delete' }).click();
        expect((await standardDeleteResponse).ok()).toBe(true);
        await page.reload();
        const exportsToggle = page.getByRole('button', { name: 'Exports' });
        if ((await exportsToggle.getAttribute('aria-expanded')) !== 'true') await exportsToggle.click();
        await expect(page.locator('#exports-collapse')).toBeVisible({ timeout: E2E_TIMEOUT.action });
        await expect(page.locator('[data-payroll-workbook-configuration]')).toHaveCount(0, { timeout: E2E_TIMEOUT.assertion });
        await expect(page.getByText('No Payroll Workbook exports configured.')).toBeVisible();
        await expect(page.getByRole('button', { name: 'Create new export' })).toBeVisible();
    });
});
