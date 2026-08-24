import { expect, test, type Page } from '@playwright/test';
import { defaultE2ERosterGroupId, ensureRosterLayout, openRoster, runSql, uniqueE2EValue } from './test-helpers';

async function ensureCompleteDraftWindow(page: Page) {
    const anchorDate = new URL(page.url()).searchParams.get('anchorDate');
    if (anchorDate === null) throw new Error('Expected canonical roster anchor date');
    runSql(`
        INSERT INTO roster_days (venue_id, roster_group_id, operational_date, publication_state, is_closed, row_count)
        SELECT
            'a1000000-0000-0000-0000-000000000001',
            '${defaultE2ERosterGroupId}',
            DATE '${anchorDate}' + day_index,
            'draft',
            FALSE,
            2
        FROM generate_series(0, 6) AS day_index
        ON CONFLICT (roster_group_id, operational_date)
        DO UPDATE SET publication_state = 'draft';
    `);
    await page.reload();
    await expect(page.locator('#roster-week-shell')).toBeVisible();
}

async function openTemplatesTab(page: Page) {
    const tab = page.getByRole('tab', { name: 'Templates', exact: true }).first();
    await expect(tab).toBeVisible();
    await tab.click();
    await expect(tab).toHaveAttribute('aria-selected', 'true');
    await expect(page.locator('#roster-staff-panel-templates-pane')).toBeVisible();
    return tab;
}

test.describe('Roster Week-template modals', () => {
    test.beforeEach(async ({ page }) => {
        await openRoster(page, { ensureDraft: true, ensureEditable: true });
        await expect(page.locator('#roster-week-shell')).toBeVisible();
    });

    test('uses the same accessible Save modal on desktop and canonical mobile', async ({ page }) => {
        await openTemplatesTab(page);
        await page.getByRole('button', { name: 'Save current week as template' }).click();

        const dialog = page.getByRole('dialog', { name: 'Save current week as template' });
        await expect(dialog).toBeVisible();
        await expect(dialog.getByLabel('Template name')).toHaveValue('');
        await expect(dialog.getByRole('radio', { name: 'Keep valid Staff assignments' })).not.toBeChecked();
        await expect(dialog.getByRole('radio', { name: 'Make every shift Open' })).not.toBeChecked();
        await expect(dialog).not.toContainText('Draft/Published');
        await expect(dialog).not.toContainText('source window');
        await dialog.getByRole('button', { name: 'Cancel' }).click();
        await expect(dialog).toBeHidden();
    });

    test('opens Apply and completes Delete on canonical mobile without losing context', async ({ page }, testInfo) => {
        test.skip(testInfo.project.name === 'desktop-chromium', 'Desktop completion is covered by the full workflow test.');
        const templateName = uniqueE2EValue('Mobile modal');
        await ensureCompleteDraftWindow(page);
        const initialUrl = page.url();

        try {
            runSql(`
                BEGIN;
                SET CONSTRAINTS roster_templates_complete_content_fk DEFERRED;
                INSERT INTO roster_templates (id, roster_group_id, name, scale, completion_id, created_by_user_id)
                VALUES (
                    md5('${templateName.replaceAll("'", "''")}-template')::uuid,
                    '${defaultE2ERosterGroupId}',
                    '${templateName.replaceAll("'", "''")}',
                    'week',
                    md5('${templateName.replaceAll("'", "''")}-completion')::uuid,
                    (SELECT id FROM users WHERE email = 'e2e-test@example.com' LIMIT 1)
                );
                INSERT INTO roster_template_days (id, roster_template_id, day_index, weekday_index, is_closed, row_count)
                SELECT
                    md5('${templateName.replaceAll("'", "''")}-day-' || day_index)::uuid,
                    md5('${templateName.replaceAll("'", "''")}-template')::uuid,
                    day_index,
                    day_index,
                    FALSE,
                    1
                FROM generate_series(0, 6) AS day_index;
                INSERT INTO roster_template_columns (roster_template_id, name, sort_order)
                VALUES (md5('${templateName.replaceAll("'", "''")}-template')::uuid, 'Only', 0);
                INSERT INTO roster_template_completions (id, roster_template_id)
                VALUES (
                    md5('${templateName.replaceAll("'", "''")}-completion')::uuid,
                    md5('${templateName.replaceAll("'", "''")}-template')::uuid
                );
                COMMIT;
            `);
            await page.reload();
            const templatesTab = await openTemplatesTab(page);
            const card = page.locator('.roster-template-card').filter({ hasText: templateName });

            await card.getByRole('button', { name: `Apply ${templateName}` }).click();
            let dialog = page.getByRole('dialog', { name: `Apply ${templateName}` });
            await expect(dialog).toBeVisible();
            await expect(dialog).toContainText('Publication remains Draft');
            await dialog.getByRole('button', { name: 'Cancel' }).click();
            await expect(dialog).toBeHidden();

            await card.getByRole('button', { name: `Delete ${templateName}` }).click();
            dialog = page.getByRole('dialog', { name: `Delete ${templateName}` });
            await expect(dialog).toBeVisible();
            const deleteResponsePromise = page.waitForResponse((response) =>
                response.request().method() === 'POST' && response.url().includes('/DeleteRosterTemplate'),
            );
            await dialog.getByRole('button', { name: 'Delete template' }).click();
            const deleteResponse = await deleteResponsePromise;
            expect(deleteResponse.status(), await deleteResponse.text()).toBe(200);
            await expect(dialog).toBeHidden();
            await expect(card).toBeHidden();
            await expect(templatesTab).toHaveAttribute('aria-selected', 'true');
            expect(page.url()).toBe(initialUrl);
        } finally {
            runSql(`
                UPDATE roster_templates
                SET deleted_at = COALESCE(deleted_at, NOW())
                WHERE name = '${templateName.replaceAll("'", "''")}';
            `);
        }
    });

    test('keeps Save and Delete available while any Published target day disables Apply', async ({ page }) => {
        const templateName = uniqueE2EValue('Published target');
        await ensureCompleteDraftWindow(page);
        const anchorDate = new URL(page.url()).searchParams.get('anchorDate');
        if (anchorDate === null) throw new Error('Expected canonical roster anchor date');

        try {
            runSql(`
                BEGIN;
                SET CONSTRAINTS roster_templates_complete_content_fk DEFERRED;
                INSERT INTO roster_templates (id, roster_group_id, name, scale, completion_id, created_by_user_id)
                VALUES (
                    md5('${templateName.replaceAll("'", "''")}-template')::uuid,
                    '${defaultE2ERosterGroupId}',
                    '${templateName.replaceAll("'", "''")}',
                    'week',
                    md5('${templateName.replaceAll("'", "''")}-completion')::uuid,
                    (SELECT id FROM users WHERE email = 'e2e-test@example.com' LIMIT 1)
                );
                INSERT INTO roster_template_days (id, roster_template_id, day_index, weekday_index, is_closed, row_count)
                SELECT
                    md5('${templateName.replaceAll("'", "''")}-day-' || day_index)::uuid,
                    md5('${templateName.replaceAll("'", "''")}-template')::uuid,
                    day_index,
                    day_index,
                    FALSE,
                    1
                FROM generate_series(0, 6) AS day_index;
                INSERT INTO roster_template_columns (roster_template_id, name, sort_order)
                VALUES (md5('${templateName.replaceAll("'", "''")}-template')::uuid, 'Only', 0);
                INSERT INTO roster_template_completions (id, roster_template_id)
                VALUES (
                    md5('${templateName.replaceAll("'", "''")}-completion')::uuid,
                    md5('${templateName.replaceAll("'", "''")}-template')::uuid
                );
                COMMIT;
                UPDATE roster_days
                SET publication_state = 'published'
                WHERE roster_group_id = '${defaultE2ERosterGroupId}'
                  AND operational_date = DATE '${anchorDate}' + 3;
            `);
            await page.reload();
            await openTemplatesTab(page);

            await expect(page.getByRole('button', { name: 'Save current week as template' })).toBeEnabled();
            await expect(page.getByText('at least one day in the viewed window is Published')).toBeVisible();
            const card = page.locator('.roster-template-card').filter({ hasText: templateName });
            await expect(card.getByRole('button', { name: `Apply ${templateName}` })).toBeDisabled();
            await expect(card.getByRole('button', { name: `Delete ${templateName}` })).toBeEnabled();
        } finally {
            runSql(`
                UPDATE roster_templates
                SET deleted_at = COALESCE(deleted_at, NOW())
                WHERE name = '${templateName.replaceAll("'", "''")}';
                UPDATE roster_days
                SET publication_state = 'draft'
                WHERE roster_group_id = '${defaultE2ERosterGroupId}'
                  AND operational_date >= DATE '${anchorDate}'
                  AND operational_date < DATE '${anchorDate}' + 7;
            `);
        }
    });

    test('saves, applies, and deletes while retaining the viewed Templates tab', async ({ page }, testInfo) => {
        test.skip(testInfo.project.name !== 'desktop-chromium', 'The durable mutation path runs once; modal rendering is covered on every canonical viewport.');
        const templateName = uniqueE2EValue('Modal week');
        await ensureRosterLayout(page, 'day_columns');
        await ensureCompleteDraftWindow(page);
        const templatesTab = await openTemplatesTab(page);

        try {
            await page.getByRole('button', { name: 'Save current week as template' }).click();
            let dialog = page.getByRole('dialog', { name: 'Save current week as template' });
            await dialog.getByLabel('Template name').fill(templateName);
            await dialog.getByRole('radio', { name: 'Make every shift Open' }).check();

            const previewResponsePromise = page.waitForResponse((response) =>
                response.request().method() === 'POST' && response.url().includes('/PreviewRosterTemplateCapture'),
            );
            await dialog.getByRole('button', { name: 'Review template' }).click();
            const previewResponse = await previewResponsePromise;
            expect(previewResponse.status(), await previewResponse.text()).toBe(200);

            dialog = page.getByRole('dialog', { name: 'Save current week as template' });
            await expect(dialog).toBeVisible();
            const saveResponsePromise = page.waitForResponse((response) =>
                response.request().method() === 'POST' && response.url().includes('/CreateRosterTemplateCapture'),
            );
            await dialog.getByRole('button', { name: 'Save template' }).click();
            const saveResponse = await saveResponsePromise;
            expect(saveResponse.status(), await saveResponse.text()).toBe(200);
            await expect(dialog).toBeHidden();
            await expect(templatesTab).toHaveAttribute('aria-selected', 'true');
            await expect(page.locator('.roster-grid-frame')).toHaveAttribute('data-roster-layout', 'day_columns');

            const card = page.locator('.roster-template-card').filter({ hasText: templateName });
            await expect(card).toBeVisible();
            await expect(card).toContainText(/\d+ shift\(s\)/);
            await expect(card).not.toContainText('Week snapshot');

            await card.getByRole('button', { name: `Apply ${templateName}` }).click();
            dialog = page.getByRole('dialog', { name: `Apply ${templateName}` });
            await expect(dialog).toContainText('entire viewed window’s operational structure');
            await expect(dialog).toContainText('Publication remains Draft');
            await expect(dialog).toContainText('Existing Timesheets');
            const applyResponsePromise = page.waitForResponse((response) =>
                response.request().method() === 'POST' && response.url().includes('/ApplyRosterTemplate'),
            );
            await dialog.getByRole('button', { name: 'Apply template' }).click();
            const applyResponse = await applyResponsePromise;
            expect(applyResponse.status(), await applyResponse.text()).toBe(200);
            await expect(dialog).toBeHidden();
            await expect(templatesTab).toHaveAttribute('aria-selected', 'true');
            await expect(page.locator('.roster-grid-frame')).toHaveAttribute('data-roster-layout', 'day_columns');

            await card.getByRole('button', { name: `Delete ${templateName}` }).click();
            dialog = page.getByRole('dialog', { name: `Delete ${templateName}` });
            await expect(dialog).toContainText('Existing rosters are unaffected');
            const deleteResponsePromise = page.waitForResponse((response) =>
                response.request().method() === 'POST' && response.url().includes('/DeleteRosterTemplate'),
            );
            await dialog.getByRole('button', { name: 'Delete template' }).click();
            const deleteResponse = await deleteResponsePromise;
            expect(deleteResponse.status(), await deleteResponse.text()).toBe(200);
            await expect(dialog).toBeHidden();
            await expect(templatesTab).toHaveAttribute('aria-selected', 'true');
            await expect(page.locator('.roster-grid-frame')).toHaveAttribute('data-roster-layout', 'day_columns');
            await expect(card).toBeHidden();
        } finally {
            runSql(`
                UPDATE roster_templates
                SET deleted_at = COALESCE(deleted_at, NOW())
                WHERE name = '${templateName.replaceAll("'", "''")}';
            `);
        }
    });
});
