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

    test('venue admin creates, edits, generates, and deletes ordered Payroll Workbook exports', async ({ page }) => {
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
        const fileName = `payroll_workbook-${currentWeek.weekStart}-to-${currentWeek.weekEnd}.xlsx`;

        const standardDownload = await generatePayrollReport(page, 'Payroll Workbook', 'Download');
        expect(standardDownload.suggestedFilename()).toBe(fileName);

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
        await addDialog.getByRole('button', { name: 'Save' }).click();

        const configurationRow = page.locator('[data-payroll-workbook-configuration]').filter({ hasText: 'Wages then Summary' });
        await expect(configurationRow).toHaveCount(1, { timeout: E2E_TIMEOUT.assertion });
        await expect(configurationRow).toContainText('Sheets: Wages by Shift Type → Summary');

        const configuredRefresh = page.waitForResponse((response) => response.url().includes('/ShowadminExportsLiveFragment'), { timeout: E2E_TIMEOUT.assertion });
        const configuredDownload = await generatePayrollReport(page, 'Wages then Summary', 'Download');
        expect(configuredDownload.suggestedFilename()).toBe(fileName);
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
        const editedDeleteRedirect = page.waitForResponse((response) => response.request().isNavigationRequest() && response.url().includes('/Admin?showExports=true'), { timeout: E2E_TIMEOUT.assertion });
        await deleteEditedDialog.getByRole('button', { name: 'Delete' }).click();
        await editedDeleteRedirect;
        await gotoExports(page);
        await expect(editedRow).toHaveCount(0, { timeout: E2E_TIMEOUT.assertion });

        const refreshedStandardCard = payrollReportCard(page, 'Payroll Workbook');
        await refreshedStandardCard.getByRole('button', { name: 'Delete' }).click();
        const deleteStandardDialog = page.getByRole('dialog', { name: 'Delete export' });
        await expect(deleteStandardDialog).toContainText('Payroll Workbook');
        const standardDeleteRedirect = page.waitForResponse((response) => response.request().isNavigationRequest() && response.url().includes('/Admin?showExports=true'), { timeout: E2E_TIMEOUT.assertion });
        await deleteStandardDialog.getByRole('button', { name: 'Delete' }).click();
        await standardDeleteRedirect;
        const exportsToggle = page.getByRole('button', { name: 'Exports' });
        if ((await exportsToggle.getAttribute('aria-expanded')) !== 'true') await exportsToggle.click();
        await expect(page.locator('#exports-collapse')).toBeVisible({ timeout: E2E_TIMEOUT.action });
        await expect(page.locator('[data-payroll-workbook-configuration]')).toHaveCount(0, { timeout: E2E_TIMEOUT.assertion });
        await expect(page.getByText('No Payroll Workbook exports configured.')).toBeVisible();
        await expect(page.getByRole('button', { name: 'Create new export' })).toBeVisible();
    });
});
