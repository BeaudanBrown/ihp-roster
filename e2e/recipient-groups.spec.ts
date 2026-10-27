import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { loginAsPrivilegedUserWithSeededPasskeySession, webauthnBaseURL } from './support/passkeys';
import { uniqueE2EValue } from './support/runtime';
import { runSql } from './support/database';

test.use({ baseURL: webauthnBaseURL });

type GroupSubscriptionWindow = Window & { __recipientGroupsSubscribed?: boolean };

test('recipient groups validate locally, retain drafts, publish updates, and confirm linked deletion', async ({ page, context }, testInfo) => {
    test.setTimeout(E2E_TIMEOUT.payrollWorkflowTest);
    const browserErrors: string[] = [];
    page.on('pageerror', error => browserErrors.push(error.message));
    const name = uniqueE2EValue(`e2e-${testInfo.project.name}-${testInfo.retry}`);
    const email = `${uniqueE2EValue('e2e-recipient')}@example.com`;
    await loginAsPrivilegedUserWithSeededPasskeySession(page);
    await page.goto('/Admin?showRecipientGroups=true');
    const surface = page.locator('[data-bepis-surface="admin-recipient-groups"]');
    await expect(surface.getByRole('button', { name: 'Create recipient group', exact: true })).toBeVisible();
    await expect(surface).toHaveAttribute('data-bepis-surface-config', /admin-recipient-groups/);

    const observer = await context.newPage();
    await observer.addInitScript(() => {
        document.addEventListener('app:live-update-debug', event => {
            const detail = (event as CustomEvent).detail;
            if (detail?.name === 'subscription_added' && detail.scopeKey?.startsWith('admin-recipient-groups:')) {
                (window as GroupSubscriptionWindow).__recipientGroupsSubscribed = true;
            }
        });
    });
    await observer.goto('/Admin?showRecipientGroups=true');
    await expect.poll(() => observer.evaluate(() => (window as GroupSubscriptionWindow).__recipientGroupsSubscribed ?? false), { timeout: E2E_TIMEOUT.liveUpdate }).toBe(true);

    await surface.getByRole('button', { name: 'Create recipient group', exact: true }).click();
    const dialog = page.getByRole('dialog', { name: 'Create recipient group', exact: true });
    await expect(dialog.getByLabel('Group name', { exact: true })).toBeFocused();
    await dialog.getByLabel('Group name', { exact: true }).fill(name);
    const entry = dialog.getByLabel('Email address', { exact: true });
    const rows = dialog.getByRole('list', { name: 'Recipient addresses' }).getByRole('listitem');
    const settled = () => expect(page.locator('#dialog-overlay-mount')).not.toHaveClass(/htmx-settling/);
    let posts = 0;
    page.on('request', request => {
        if (request.method() === 'POST' && new URL(request.url()).pathname === '/SaveRecipientGroup') posts += 1;
    });
    await entry.fill('not-an-email');
    await dialog.getByRole('button', { name: 'Add', exact: true }).click();
    await expect(entry).toBeFocused();
    expect(await entry.evaluate(input => (input as HTMLInputElement).validity.typeMismatch)).toBe(true);
    expect(posts).toBe(0);
    await entry.press('Enter');
    expect(posts).toBe(0);
    await expect(rows).toHaveCount(0);

    await entry.fill(email);
    await dialog.getByRole('button', { name: 'Add', exact: true }).click();
    await expect(rows).toHaveCount(1);
    await expect(entry).toHaveValue('');
    await expect(entry).toBeFocused();
    await settled();
    await expect(dialog.getByLabel('Group name', { exact: true })).toHaveValue(name);
    await entry.fill(email.toUpperCase());
    await entry.press('Enter');
    await expect(entry).toHaveValue('');
    await expect(rows).toHaveCount(1);
    await settled();
    await entry.fill('remove-me@example.com');
    await entry.press('Enter');
    await expect(rows).toHaveCount(2);
    await settled();
    await entry.fill('invalid-pending');
    await dialog.getByRole('button', { name: 'Remove remove-me@example.com', exact: true }).press('Enter');
    await expect(rows).toHaveCount(1);
    await expect(entry).toHaveValue('invalid-pending');
    await settled();
    await entry.fill('');
    await page.screenshot({ path: `output/recipient-groups/${testInfo.project.name}-editor.png`, fullPage: true });
    expect(await dialog.evaluate(node => node.scrollWidth > node.clientWidth)).toBe(false);

    const saveResponse = page.waitForResponse(response => response.request().method() === 'POST' && new URL(response.url()).pathname === '/SaveRecipientGroup');
    await dialog.getByRole('button', { name: 'Save', exact: true }).press('Enter');
    const headers = (await saveResponse).headers();
    expect(headers['hx-trigger']).toContain('admin-recipient-groups');
    expect(headers['hx-trigger']).not.toContain(email);
    await expect(dialog).toHaveCount(0);
    const card = surface.getByRole('group', { name, exact: true });
    await expect(card).toBeVisible();
    await expect(card).toContainText('1 recipient');
    await expect(observer.getByRole('group', { name, exact: true })).toBeVisible({ timeout: E2E_TIMEOUT.liveUpdate });
    await observer.close();

    await card.getByRole('button', { name: 'Edit', exact: true }).click();
    const edit = page.getByRole('dialog', { name: 'Edit recipient group', exact: true });
    await expect(edit.getByRole('listitem')).toContainText(email);
    await edit.getByLabel('Email address', { exact: true }).fill('invalid-pending');
    await edit.getByRole('button', { name: 'Cancel', exact: true }).press('Enter');
    await expect(edit).toHaveCount(0);

    // Disposable E2E fixture only: link an enabled schedule to the UI-created group.
    runSql(`
        INSERT INTO payroll_workbook_configurations (id, venue_id, name, definition_version, revision, created_by_user_id)
        VALUES ('a1000000-0000-0000-0000-000000000898', 'a1000000-0000-0000-0000-000000000001', 'Recipient group deletion fixture', 1, 0, 'a0000000-0000-0000-0000-000000000003')
        ON CONFLICT (id) DO NOTHING;
        INSERT INTO payroll_workbook_configuration_families (configuration_id, family_key, position)
        VALUES ('a1000000-0000-0000-0000-000000000898', 'summary', 0)
        ON CONFLICT (configuration_id, family_key) DO NOTHING;
        INSERT INTO payroll_report_settings (venue_id, configuration_id, recipients, enabled, recipient_group_id, updated_by_user_id)
        SELECT venue_id, 'a1000000-0000-0000-0000-000000000898', recipients, true, id, updated_by_user_id
        FROM recipient_groups WHERE name = '${name}' AND venue_id = 'a1000000-0000-0000-0000-000000000001' AND archived_at IS NULL
        ON CONFLICT (venue_id) DO UPDATE SET configuration_id = EXCLUDED.configuration_id, recipient_group_id = EXCLUDED.recipient_group_id, enabled = true;
    `);
    await card.getByRole('button', { name: 'Delete', exact: true }).click();
    const confirmation = page.getByRole('dialog', { name: 'Delete recipient group', exact: true });
    await expect(confirmation).toContainText('disables that schedule');
    await expect(confirmation).toContainText('Prepared manual emails keep their original recipients');
    await page.screenshot({ path: `output/recipient-groups/${testInfo.project.name}-linked-delete.png`, fullPage: true });
    expect(await confirmation.evaluate(node => node.scrollWidth > node.clientWidth)).toBe(false);
    expect(await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth)).toBe(false);
    const approve = confirmation.getByRole('button', { name: 'Delete group and disable schedule', exact: true });
    expect(await approve.evaluate(node => (node as HTMLButtonElement).form?.id)).toBe('recipient-group-delete-form');
    expect(await approve.evaluate(node => (node as HTMLButtonElement).form?.checkValidity())).toBe(true);
    await expect(confirmation.locator('#recipient-group-delete-form')).toHaveAttribute('hx-delete', /\/DeleteRecipientGroup\?/);
    await approve.click();
    expect(browserErrors).toEqual([]);
    await expect(confirmation).toHaveCount(0);
    await expect(card).toHaveCount(0);
});
