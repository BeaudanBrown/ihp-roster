import { expect, test, type Page } from '@playwright/test';
import { defaultE2ERosterGroupId, E2E_TIMEOUT, ensureRosterLayout, gotoWhenReady, openRoster, querySql, runSql, uniqueE2EValue } from './test-helpers';

function disconnectDurableInvalidationListeners() {
    const listenerCount = Number(querySql(`
        SELECT COUNT(*)
        FROM pg_stat_activity
        WHERE application_name = 'bepis-live-invalidation-listener'
          AND datname = current_database();
    `).trim());
    expect(listenerCount).toBeGreaterThan(0);
    runSql(`
        SELECT pg_terminate_backend(pid)
        FROM pg_stat_activity
        WHERE application_name = 'bepis-live-invalidation-listener'
          AND datname = current_database();
    `);
    expect(Number(querySql(`
        SELECT COUNT(*)
        FROM pg_stat_activity
        WHERE application_name = 'bepis-live-invalidation-listener'
          AND datname = current_database();
    `).trim())).toBe(0);
}

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
    test('does not expose retired template-authoring routes', async ({ request }) => {
        const templateId = '00000000-0000-0000-0000-000000000001';
        const group = `rosterGroupId=${defaultE2ERosterGroupId}`;
        const design = `rosterTemplateDesignId=${templateId}`;
        const retiredRoutes = [
            `/NewRosterTemplate?${group}`,
            `/CreateRosterTemplateDraft?${group}`,
            `/ShowRosterTemplateReference?${group}&weekOffset=0`,
            `/ConfirmRosterTemplateReference?${group}&weekOffset=0`,
            `/CreateRosterTemplateFromReference?${group}&weekOffset=0`,
            `/DiscardAndRestartRosterTemplateDraft?${group}&${design}`,
            `/ShowRosterTemplateDesigner?${design}`,
            `/UpdateRosterTemplateDay?${design}&dayIndex=0`,
            `/AddRosterTemplateColumn?${design}`,
            `/UpdateRosterTemplateColumn?${design}&columnSortOrder=0`,
            `/DeleteRosterTemplateColumn?${design}&columnSortOrder=0`,
            `/UpsertRosterTemplateShift?${design}`,
            `/DeleteRosterTemplateShift?${design}&dayIndex=0&columnSortOrder=0&rowIndex=0`,
            `/SaveRosterTemplate?${design}`,
            `/ReloadRosterTemplateDraft?${design}`,
            `/SaveRosterTemplateDraftAsNew?${design}`,
            `/EditRosterTemplate?rosterTemplateId=${templateId}`,
        ];

        for (const route of retiredRoutes) {
            const response = await request.get(route, { maxRedirects: 0 });
            expect(response.status(), route).toBe(404);
        }
    });

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

    test('converges the shared library across two mounted editors after Save, Apply, and Delete', async ({ page }, testInfo) => {
        const viewerPage = await page.context().newPage();
        const templateName = uniqueE2EValue('Shared live template');
        try {
            await ensureCompleteDraftWindow(page);
            const actorUrl = new URL(page.url());
            await gotoWhenReady(viewerPage, actorUrl.pathname + actorUrl.search, '#roster-week-shell');
            const actorTemplatesTab = await openTemplatesTab(page);
            const viewerTemplatesTab = await openTemplatesTab(viewerPage);

            await page.getByRole('button', { name: 'Save current week as template' }).click();
            let dialog = page.getByRole('dialog', { name: 'Save current week as template' });
            await dialog.getByLabel('Template name').fill(templateName);
            await dialog.getByRole('radio', { name: 'Keep valid Staff assignments' }).check();
            await dialog.getByRole('button', { name: 'Review template' }).click();
            dialog = page.getByRole('dialog', { name: 'Save current week as template' });
            await dialog.getByRole('button', { name: 'Save template' }).click();

            const actorCard = page.locator('.roster-template-card').filter({ hasText: templateName });
            const viewerCard = viewerPage.locator('.roster-template-card').filter({ hasText: templateName });
            await expect(actorCard).toBeVisible({ timeout: E2E_TIMEOUT.liveUpdate });
            await expect(viewerCard).toBeVisible({ timeout: E2E_TIMEOUT.liveUpdate });

            const actorApplyRefresh = page.waitForResponse((response) =>
                response.request().method() === 'GET' && response.url().includes('/ShowRosterTemplateLibraryFragment'),
            );
            const passiveApplyRefresh = viewerPage.waitForResponse((response) =>
                response.request().method() === 'GET' && response.url().includes('/ShowRosterTemplateLibraryFragment'),
            );
            const applyButton = actorCard.getByRole('button', { name: `Apply ${templateName}` });
            await applyButton.evaluate((button: HTMLButtonElement) => button.form?.requestSubmit(button));
            dialog = page.getByRole('dialog', { name: `Apply ${templateName}` });
            await dialog.getByRole('button', { name: 'Apply template' }).click();
            expect((await actorApplyRefresh).status()).toBe(200);
            expect((await passiveApplyRefresh).status()).toBe(200);
            await expect(dialog).toBeHidden({ timeout: E2E_TIMEOUT.liveUpdate });
            await expect(actorCard).toBeVisible();
            await expect(viewerCard).toBeVisible();
            await page.reload();
            await openTemplatesTab(page);
            await expect(actorCard).toBeVisible();

            const deleteButton = actorCard.getByRole('button', { name: `Delete ${templateName}` });
            await deleteButton.evaluate((button: HTMLButtonElement) => button.form?.requestSubmit(button));
            dialog = page.getByRole('dialog', { name: `Delete ${templateName}` });
            await expect(dialog).toBeVisible();
            const preDisconnectEventSequence = testInfo.project.name === 'desktop-chromium'
                ? Number(querySql(`
                    SELECT COALESCE(MAX(sequence_number), 0)
                    FROM live_invalidation_events;
                `).trim())
                : null;
            if (preDisconnectEventSequence !== null) disconnectDurableInvalidationListeners();
            await dialog.getByRole('button', { name: 'Delete template' }).click();
            await expect(actorCard).toBeHidden({ timeout: E2E_TIMEOUT.liveUpdate });
            await expect(viewerCard).toBeHidden({ timeout: E2E_TIMEOUT.liveUpdate });
            if (preDisconnectEventSequence !== null) {
                await expect.poll(() => querySql(`
                    SELECT EXISTS (
                        SELECT 1
                        FROM pg_stat_activity listener
                        JOIN live_invalidation_events event
                          ON event.source = 'roster.template.delete'
                        WHERE listener.application_name = 'bepis-live-invalidation-listener'
                          AND listener.datname = current_database()
                          AND event.sequence_number > ${preDisconnectEventSequence}
                          AND listener.backend_start > event.created_at
                        ORDER BY event.sequence_number DESC
                        LIMIT 1
                    );
                `).trim(), { timeout: E2E_TIMEOUT.liveUpdate }).toBe('t');
            }
            await expect(actorTemplatesTab).toHaveAttribute('aria-selected', 'true');
            await expect(viewerTemplatesTab).toHaveAttribute('aria-selected', 'true');
        } finally {
            await viewerPage.close();
            runSql(`
                UPDATE roster_templates
                SET deleted_at = COALESCE(deleted_at, NOW())
                WHERE name = '${templateName.replaceAll("'", "''")}';
            `);
        }
    });

    test('opens Apply and completes Delete across canonical viewports without losing context', async ({ page }) => {
        const templateName = uniqueE2EValue('Mobile modal');
        await ensureCompleteDraftWindow(page);
        const initialUrl = page.url();

        try {
            runSql(`
                DELETE FROM roster_templates
                WHERE name = '${templateName.replaceAll("'", "''")}';
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

            await card.getByRole('button', { name: `Apply ${templateName}` }).evaluate((button: HTMLButtonElement) => button.click());
            let dialog = page.getByRole('dialog', { name: `Apply ${templateName}` });
            await expect(dialog).toBeVisible();
            await expect(dialog).toContainText('Publication remains Draft');
            await dialog.getByRole('button', { name: 'Cancel' }).click();
            await expect(dialog).toBeHidden();

            await card.getByRole('button', { name: `Delete ${templateName}` }).evaluate((button: HTMLButtonElement) => button.click());
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
                DELETE FROM roster_templates
                WHERE name = '${templateName.replaceAll("'", "''")}';
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

    test('saves, applies, and deletes while retaining the viewed Templates tab', async ({ page }) => {
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

            const applyButton = card.getByRole('button', { name: `Apply ${templateName}` });
            await applyButton.evaluate((button: HTMLButtonElement) => button.form?.requestSubmit(button));
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
            await page.reload();
            await openTemplatesTab(page);
            await expect(card).toBeVisible();

            const deleteButton = card.getByRole('button', { name: `Delete ${templateName}` });
            await deleteButton.evaluate((button: HTMLButtonElement) => button.form?.requestSubmit(button));
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
