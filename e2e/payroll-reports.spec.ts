import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { gotoExports } from './support/exports';
import { loginAsPrivilegedUserWithSeededPasskeySession, webauthnBaseURL } from './support/passkeys';
import { runSql } from './support/database';

test.use({ baseURL: webauthnBaseURL });

test('scheduled reports enable group selections at 06:00 and preserve them while disabled', async ({ page }, testInfo) => {
    test.setTimeout(E2E_TIMEOUT.payrollWorkflowTest);
    runSql(`
        DELETE FROM payroll_report_runs WHERE venue_id = 'a1000000-0000-0000-0000-000000000001';
        DELETE FROM payroll_report_settings WHERE venue_id = 'a1000000-0000-0000-0000-000000000001';
        INSERT INTO payroll_workbook_configurations (id, venue_id, name, definition_version, revision, created_by_user_id)
        VALUES ('a1000000-0000-0000-0000-000000000899', 'a1000000-0000-0000-0000-000000000001', 'Scheduled test payroll', 1, 0, 'a0000000-0000-0000-0000-000000000003')
        ON CONFLICT (id) DO NOTHING;
        INSERT INTO payroll_workbook_configuration_families (configuration_id, family_key, position)
        VALUES ('a1000000-0000-0000-0000-000000000899', 'summary', 0)
        ON CONFLICT (configuration_id, family_key) DO NOTHING;
        INSERT INTO recipient_groups (id, venue_id, name, recipients, created_by_user_id, updated_by_user_id)
        VALUES ('a1000000-0000-0000-0000-000000000897', 'a1000000-0000-0000-0000-000000000001', 'Scheduled payroll recipients', ARRAY['e2e-scheduled@example.com'], 'a0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000003')
        ON CONFLICT (id) DO UPDATE SET archived_at = NULL;
    `);
    await loginAsPrivilegedUserWithSeededPasskeySession(page);
    await gotoExports(page);
    await page.getByRole('button', { name: 'Scheduled reports', exact: true }).click();
    const dialog = page.getByRole('dialog', { name: 'Scheduled reports', exact: true });
    await expect(dialog).toBeVisible();
    const toggle = dialog.getByRole('checkbox', { name: 'Enable automatic weekly reports', exact: true });
    const toggleLabel = dialog.getByText('Enable automatic weekly reports', { exact: true });
    const template = dialog.getByLabel('Export template', { exact: true });
    const group = dialog.getByLabel('Recipient group', { exact: true });
    const save = dialog.getByRole('button', { name: 'Save', exact: true });
    const settled = () => expect(page.locator('#dialog-overlay-mount')).not.toHaveClass(/htmx-settling/);
    expect(await dialog.locator('input[type="checkbox"], select').evaluateAll(nodes => nodes.map(node => node.id)))
        .toEqual(['report-enabled', 'report-template', 'report-group']);
    await expect(toggle).not.toBeChecked();
    await expect(template).toBeDisabled();
    await expect(group).toBeDisabled();
    await expect(dialog).toContainText('06:00 venue-local');
    await expect(dialog.locator('input[type="time"], input[type="email"]')).toHaveCount(0);
    await expect(dialog.getByLabel('Reporting week', { exact: true })).toHaveCount(0);
    await expect(dialog.getByRole('button', { name: 'Review and send', exact: true })).toHaveCount(0);
    await expect(dialog.getByText('Last four reporting weeks', { exact: true })).toHaveCount(0);
    await save.click();
    await expect(dialog.getByRole('status')).toContainText('settings saved');
    await settled();
    await toggleLabel.click();
    await expect(toggle).toBeChecked();
    await expect(template).toBeEnabled();
    await expect(group).toBeEnabled();
    await template.selectOption({ label: 'Scheduled test payroll' });
    await save.click();
    await expect(dialog.getByRole('status')).toContainText('Choose an available recipient group');
    await expect(template).toHaveValue('a1000000-0000-0000-0000-000000000899');
    await settled();
    await group.selectOption({ label: 'Scheduled payroll recipients' });
    await save.click();
    await expect(dialog.getByRole('status')).toContainText('settings saved');
    await expect(dialog).toContainText('Scheduled for');
    await settled();
    await page.screenshot({ path: `output/payroll-reports/${testInfo.project.name}-settings.png`, fullPage: true });
    await toggleLabel.click();
    await expect(template).toBeDisabled();
    await expect(group).toBeDisabled();
    await save.click();
    await expect(dialog.getByRole('status')).toContainText('settings saved');
    await expect(toggle).not.toBeChecked();
    await expect(template).toHaveValue('a1000000-0000-0000-0000-000000000899');
    await expect(group).toHaveValue('a1000000-0000-0000-0000-000000000897');
    await settled();
    await page.screenshot({ path: `output/payroll-reports/${testInfo.project.name}-disabled-settings.png`, fullPage: true });
    expect(await dialog.evaluate(node => node.scrollWidth > node.clientWidth)).toBe(false);
    expect(await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth)).toBe(false);
    runSql(`DO $$ BEGIN
        IF NOT EXISTS (SELECT 1 FROM payroll_report_settings
            WHERE venue_id = 'a1000000-0000-0000-0000-000000000001' AND NOT enabled AND minute_of_day = 360
              AND configuration_id = 'a1000000-0000-0000-0000-000000000899'
              AND recipient_group_id = 'a1000000-0000-0000-0000-000000000897')
        THEN RAISE EXCEPTION 'disabled schedule did not preserve selections and 06:00 default'; END IF;
    END $$;`);
    await toggleLabel.click();
    await save.click();
    await expect(dialog.getByRole('status')).toContainText('settings saved');
    await settled();
    await dialog.getByRole('button', { name: 'Cancel', exact: true }).click();
    const card = page.locator('[data-payroll-workbook-configuration="a1000000-0000-0000-0000-000000000899"]');
    await card.getByRole('button', { name: 'Delete', exact: true }).click();
    const confirmation = page.getByRole('dialog', { name: 'Delete export', exact: true });
    await expect(confirmation).toContainText('disables automatic reports');
    await confirmation.getByRole('button', { name: 'Delete', exact: true }).click();
    await expect(confirmation).toHaveCount(0);
    await expect(card).toHaveCount(0);
    await page.getByRole('button', { name: 'Scheduled reports', exact: true }).click();
    await expect(toggle).not.toBeChecked();
    await expect(group).toHaveValue('a1000000-0000-0000-0000-000000000897');
    await expect(template).toHaveValue('');
    await dialog.getByRole('link', { name: 'Manage recipient groups', exact: true }).click();
    await expect(page).toHaveURL(/showRecipientGroups=true/);
    await expect(page.getByRole('button', { name: 'Create recipient group', exact: true })).toBeVisible();
});
