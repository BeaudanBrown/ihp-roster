import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { gotoExports } from './support/exports';
import { loginAsPrivilegedUserWithSeededPasskeySession, webauthnBaseURL } from './support/passkeys';
import { runSql } from './support/database';

test.use({ baseURL: webauthnBaseURL });

test('scheduled payroll modal supports manual-only settings, confirmation and updated history', async ({ page }, testInfo) => {
    test.setTimeout(E2E_TIMEOUT.payrollWorkflowTest);
    runSql(`
        DELETE FROM payroll_report_runs WHERE venue_id = 'a1000000-0000-0000-0000-000000000001';
        DELETE FROM payroll_report_settings WHERE venue_id = 'a1000000-0000-0000-0000-000000000001';
        INSERT INTO payroll_workbook_configurations (id, venue_id, name, definition_version, revision, created_by_user_id)
        VALUES ('a1000000-0000-0000-0000-000000000899', 'a1000000-0000-0000-0000-000000000001', 'Scheduled test payroll', 1, 0, 'a0000000-0000-0000-0000-000000000003')
        ON CONFLICT (id) DO NOTHING;
        INSERT INTO payroll_workbook_configuration_families (configuration_id, family_key, position)
        SELECT 'a1000000-0000-0000-0000-000000000899', 'summary', 0
        WHERE NOT EXISTS (SELECT 1 FROM payroll_workbook_configuration_families WHERE configuration_id = 'a1000000-0000-0000-0000-000000000899');
    `);
    await loginAsPrivilegedUserWithSeededPasskeySession(page);
    await gotoExports(page);
    await page.getByRole('button', { name: 'Scheduled reports', exact: true }).click();
    const dialog = page.getByRole('dialog', { name: 'Scheduled reports', exact: true });
    await expect(dialog).toBeVisible();
    const emailEntry = dialog.getByLabel('Recipients', { exact: true });
    const recipientRows = dialog.getByRole('list', { name: 'Report recipients' }).getByRole('listitem');
    const sendTime = dialog.getByLabel('Send time on the first day of each roster week');
    await expect(sendTime).toHaveValue('09:00');
    await expect(dialog.getByLabel('Send day', { exact: true })).toHaveCount(0);
    await expect(dialog.getByLabel('I am authorised', { exact: false })).toHaveCount(0);
    await dialog.getByLabel('Saved payroll template').selectOption({ label: 'Scheduled test payroll' });
    await sendTime.fill('09:30');
    await emailEntry.fill('invalid-address');
    await dialog.getByRole('button', { name: 'Add', exact: true }).click();
    await expect(dialog.getByRole('status')).toContainText('Enter valid email addresses');
    await emailEntry.fill('e2e-payroll-report@example.com');
    await dialog.getByRole('button', { name: 'Add', exact: true }).click();
    await expect(recipientRows).toHaveCount(1);
    await expect(emailEntry).toHaveValue('');
    await expect(sendTime).toHaveValue('09:30');
    await emailEntry.fill('E2E-PAYROLL-REPORT@example.com');
    await emailEntry.press('Enter');
    await expect(emailEntry).toHaveValue('');
    await expect(recipientRows).toHaveCount(1);
    await emailEntry.fill('remove-me@example.com');
    await dialog.getByRole('button', { name: 'Add', exact: true }).click();
    await expect(recipientRows).toHaveCount(2);
    await dialog.getByRole('button', { name: 'Remove remove-me@example.com', exact: true }).click();
    await expect(recipientRows).toHaveCount(1);
    await dialog.getByRole('button', { name: 'Save', exact: true }).click();
    await expect(dialog.getByRole('status')).toContainText('settings saved');
    await expect(dialog.getByLabel('Enable automatic weekly reports')).not.toBeChecked();
    const reportingWeek = await dialog.locator('input[name="reportWeek"]').inputValue();
    await dialog.getByRole('button', { name: 'Review send', exact: true }).click();
    const confirmation = page.getByRole('dialog', { name: 'Confirm payroll email', exact: true });
    await expect(confirmation).toContainText(reportingWeek);
    await expect(confirmation).toContainText('e2e-payroll-report@example.com');
    await expect(confirmation).toContainText('no-data email');
    await confirmation.getByRole('button', { name: 'Send to entire list', exact: true }).click();
    await expect(dialog.getByRole('status')).toContainText('Report prepared');
    await expect(dialog.getByRole('heading', { name: new RegExp(reportingWeek) })).toBeVisible();
    await dialog.getByRole('button', { name: 'Review updated resend', exact: true }).click();
    await expect(confirmation).toContainText('entire current list receives another copy');
    await expect(confirmation).toContainText('not a replay');
    await page.screenshot({ path: `output/payroll-reports/${testInfo.project.name}-resend-confirmation.png`, fullPage: true });
    await confirmation.getByRole('button', { name: 'Cancel', exact: true }).click();
    await page.getByRole('button', { name: 'Scheduled reports', exact: true }).click();
    await dialog.getByLabel('Enable automatic weekly reports').check();
    await dialog.getByRole('button', { name: 'Save', exact: true }).click();
    await expect(dialog.getByRole('status')).toContainText('settings saved');
    await expect(dialog).toContainText('Scheduled for');
    await page.screenshot({ path: `output/payroll-reports/${testInfo.project.name}-settings.png`, fullPage: true });
    const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
    expect(hasHorizontalOverflow).toBe(false);
    await dialog.getByRole('button', { name: 'Review send', exact: true }).click();
    await expect(confirmation).toContainText('does not suppress it');
});
