import { test, expect } from '@playwright/test';
import { randomUUID } from 'node:crypto';
import { gotoWhenReady } from './support/runtime';
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

test('export email reviews current recipients and confirms repeats with Send again', async ({ page }, testInfo) => {
    test.setTimeout(E2E_TIMEOUT.payrollWorkflowTest);
    const templateId = randomUUID();
    const groupId = randomUUID();
    const otherGroupId = randomUUID();
    const suffix = templateId.slice(0, 8);
    const address = `e2e-${suffix}@example.com`;
    const changedAddress = `e2e-new-${suffix}@example.com`;
    const otherAddress = `e2e-other-${suffix}@example.com`;
    runSql(`
        INSERT INTO payroll_workbook_configurations (id, venue_id, name, definition_version, revision, created_by_user_id)
        VALUES ('${templateId}', 'a1000000-0000-0000-0000-000000000001', 'Email template ${suffix}', 1, 0, 'a0000000-0000-0000-0000-000000000003');
        INSERT INTO payroll_workbook_configuration_families (configuration_id, family_key, position) VALUES ('${templateId}', 'summary', 0);
        INSERT INTO recipient_groups (id, venue_id, name, recipients, created_by_user_id, updated_by_user_id) VALUES
        ('${groupId}', 'a1000000-0000-0000-0000-000000000001', 'Email group ${suffix}', ARRAY['${address}'], 'a0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000003'),
        ('${otherGroupId}', 'a1000000-0000-0000-0000-000000000001', 'Other email group ${suffix}', ARRAY['${otherAddress}'], 'a0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000003');
        INSERT INTO payroll_report_settings (venue_id, enabled, recipient_group_id, updated_by_user_id)
        VALUES ('a1000000-0000-0000-0000-000000000001', false, '${groupId}', 'a0000000-0000-0000-0000-000000000003')
        ON CONFLICT (venue_id) DO UPDATE SET enabled = false, recipient_group_id = EXCLUDED.recipient_group_id;
    `);
    await loginAsPrivilegedUserWithSeededPasskeySession(page);
    await gotoExports(page);
    const card = page.locator(`[data-payroll-workbook-configuration="${templateId}"]`);
    await expect(card.getByRole('button', { name: 'Email…', exact: true })).toBeDisabled();
    await expect(page.getByText('Email is available only for completed roster weeks.', { exact: false })).toBeVisible();
    await gotoWhenReady(page, '/Admin?showExports=true&anchorDate=2025-01-06#exports', 'h1:has-text("Admin")');
    await card.getByRole('button', { name: 'Email…', exact: true }).click();
    const chooser = page.getByRole('dialog', { name: 'Email export', exact: true });
    const confirmation = page.getByRole('dialog', { name: 'Confirm payroll email', exact: true });
    const settled = () => expect(page.locator('#dialog-overlay-mount')).not.toHaveClass(/htmx-settling/);
    await expect(chooser.getByLabel('Recipient group', { exact: true })).toHaveValue(groupId);
    await expect(chooser).toContainText(`Email template ${suffix}`);
    await expect(chooser).toContainText('2025-01-06 – 2025-01-12');
    await expect(chooser.getByRole('link', { name: 'Manage recipient groups', exact: true })).toHaveCount(0);
    await expect(chooser).not.toContainText('download filters do not apply');
    await chooser.getByLabel('Recipient group', { exact: true }).selectOption(otherGroupId);
    await chooser.getByRole('button', { name: 'Review recipients', exact: true }).click();
    await expect(confirmation.getByText(otherAddress, { exact: true })).toBeVisible();
    await settled();
    await confirmation.getByRole('button', { name: 'Back', exact: true }).click();
    await expect(chooser.getByLabel('Recipient group', { exact: true })).toHaveValue(otherGroupId);
    await expect(chooser).toContainText('2025-01-06 – 2025-01-12');
    await settled();
    await chooser.getByLabel('Recipient group', { exact: true }).selectOption(groupId);
    await chooser.getByRole('button', { name: 'Review recipients', exact: true }).click();
    await expect(confirmation.getByText(address, { exact: true })).toBeVisible();
    await expect(confirmation.getByRole('checkbox')).toHaveCount(0);
    await settled();
    runSql(`UPDATE recipient_groups SET recipients = ARRAY['${changedAddress}'], revision = revision + 1 WHERE id = '${groupId}';`);
    await confirmation.getByRole('button', { name: 'Send email', exact: true }).click();
    await expect(confirmation.getByRole('status')).toContainText('Review the send confirmation again');
    await expect(confirmation.getByText(changedAddress, { exact: true })).toBeVisible();
    await expect(confirmation.getByText(address, { exact: true })).toHaveCount(0);
    await settled();
    await page.screenshot({ path: `output/payroll-reports/${testInfo.project.name}-email-confirmation.png`, fullPage: true });
    await confirmation.getByRole('button', { name: 'Send email', exact: true }).click();
    await expect(confirmation).toHaveCount(0);
    await expect(chooser).toHaveCount(0);
    await expect(page.getByText('Report queued for delivery', { exact: true })).toBeVisible();
    await settled();
    await card.getByRole('button', { name: 'Email…', exact: true }).click();
    await expect(chooser.getByLabel('Recipient group', { exact: true })).toHaveValue(groupId);
    await chooser.getByLabel('Recipient group', { exact: true }).selectOption(otherGroupId);
    await chooser.getByRole('button', { name: 'Review recipients', exact: true }).click();
    await expect(confirmation.getByText(otherAddress, { exact: true })).toBeVisible();
    await expect(confirmation.getByRole('alert')).toContainText('This sends a new copy to this group.');
    await expect(confirmation.getByRole('checkbox')).toHaveCount(0);
    await expect(confirmation.getByRole('button', { name: 'Send again', exact: true })).toBeEnabled();
    await settled();
    runSql(`DO $$ BEGIN IF (SELECT count(*) FROM payroll_report_runs WHERE configuration_id = '${templateId}') <> 1
        THEN RAISE EXCEPTION 'review created another run before Send again'; END IF; END $$;`);
    await page.screenshot({ path: `output/payroll-reports/${testInfo.project.name}-email-repeat-confirmation.png`, fullPage: true });
    expect(await confirmation.evaluate(node => node.scrollWidth > node.clientWidth)).toBe(false);
    expect(await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth)).toBe(false);
    await confirmation.getByRole('button', { name: 'Send again', exact: true }).click();
    await expect(confirmation).toHaveCount(0);
    await expect(chooser).toHaveCount(0);
    await expect(page.getByText('Report queued for delivery', { exact: true })).toBeVisible();
    runSql(`DO $$ BEGIN
        IF (SELECT count(*) FROM payroll_report_runs WHERE configuration_id = '${templateId}' AND reporting_week = DATE '2025-01-06' AND settings_id IS NULL AND export_job_id IS NULL) <> 2
        THEN RAISE EXCEPTION 'email selection or no-data snapshot mismatch'; END IF;
        IF NOT EXISTS (SELECT 1 FROM payroll_report_runs WHERE configuration_id = '${templateId}' AND recipients = ARRAY['${changedAddress}'])
        THEN RAISE EXCEPTION 'accepted recipient snapshot mismatch'; END IF;
    END $$;`);
});
