import { expect, test, type Page } from '@playwright/test';
import {
    defaultE2ERosterGroupId,
    E2E_TIMEOUT,
    gotoWhenReady,
    loginAs,
    openRoster,
    runSql,
} from './test-helpers';

const managerEmail = 'e2e-admin@example.com';
const password = 'test-password-123';

function resetTemplates() {
    runSql(`
        TRUNCATE roster_template_shifts, roster_template_columns, roster_template_days,
            roster_template_designs, roster_templates;
        UPDATE roster_days
        SET publication_state = 'draft'
        WHERE roster_group_id = '${defaultE2ERosterGroupId}';
    `);
    resetApplicationTargetState();
}

function resetApplicationTargetState() {
    runSql(`
        UPDATE roster_days
        SET is_closed = FALSE, row_count = 4, publication_state = 'draft'
        WHERE roster_group_id = '${defaultE2ERosterGroupId}'
          AND operational_date BETWEEN CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)
              AND CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 6;
        UPDATE roster_lanes
        SET deleted_at = CASE
                WHEN id = 'a1000000-0000-0000-0000-000000000081' THEN NULL
                ELSE COALESCE(deleted_at, NOW())
            END,
            deleted_by_user_id = NULL,
            delete_reason = CASE
                WHEN id = 'a1000000-0000-0000-0000-000000000081' THEN NULL
                ELSE 'e2e_template_acceptance_reset'
            END
        WHERE roster_day_id IN (
            SELECT id FROM roster_days
            WHERE roster_group_id = '${defaultE2ERosterGroupId}'
              AND operational_date BETWEEN CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)
                  AND CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 6
        );
        UPDATE roster_slots
        SET deleted_at = NULL, deleted_by_user_id = NULL, delete_reason = NULL
        WHERE id = 'a1000000-0000-0000-0000-000000000071';
    `);
}

async function createBlankTemplate(page: Page, name: string, scale: 'Day' | 'Week') {
    await gotoWhenReady(page, `/NewRosterTemplate?rosterGroupId=${defaultE2ERosterGroupId}`, '#roster-template-create');
    await page.getByRole('radio', { name: scale, exact: true }).check();
    await page.getByLabel('Template name').fill(name);
    await page.getByLabel(/Start from a blank design/).check();
    await page.getByRole('button', { name: 'Continue' }).click();
    await expect(page).toHaveURL(/ShowRosterTemplateDesigner/, { timeout: E2E_TIMEOUT.navigation });
    await page.getByRole('button', { name: 'Save template' }).click();
    await expect(page).toHaveURL(/NewRosterTemplate/, { timeout: E2E_TIMEOUT.navigation });
}

async function openTemplatesTab(page: Page) {
    await page.getByRole('tab', { name: 'Templates' }).click();
    await expect(page.getByRole('heading', { name: 'Templates', exact: true })).toBeVisible();
}

test.beforeEach(() => {
    test.skip(true, 'Templates are intentionally hidden from the Roster side panel for the next release.');
});

test.afterEach(() => {
    resetApplicationTargetState();
});

test.beforeEach(async ({ page }) => {
    resetTemplates();
    await loginAs(page, managerEmail, password);
    await createBlankTemplate(page, 'Lunch service', 'Day');
    await createBlankTemplate(page, 'Standard week', 'Week');
    runSql(`
        INSERT INTO roster_days (venue_id, roster_group_id, operational_date, publication_state, is_closed, row_count)
        SELECT
            'a1000000-0000-0000-0000-000000000001', '${defaultE2ERosterGroupId}',
            CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + day_index,
            'draft', FALSE, 2
        FROM generate_series(0, 6) AS day_index
        ON CONFLICT (roster_group_id, operational_date) DO NOTHING;
    `);
    await gotoWhenReady(page, '/RosterWeeks', '#roster-content');
    await openRoster(page, { email: managerEmail, useCurrentSession: true });
    await openTemplatesTab(page);
});

test('live roster explains rejection and exposes no application targets', async ({ page }, testInfo) => {
    test.skip(testInfo.project.name !== 'desktop-chromium', 'Live-target rejection is covered once on desktop.');
    const viewedUrl = new URL(page.url());
    const viewedAnchorDate = viewedUrl.searchParams.get('anchorDate');
    if (viewedAnchorDate === null) throw new Error('Expected canonical roster anchor date');
    runSql(`
        UPDATE roster_days
        SET publication_state = 'published'
        WHERE roster_group_id = '${defaultE2ERosterGroupId}'
          AND operational_date >= '${viewedAnchorDate}'::date
          AND operational_date < '${viewedAnchorDate}'::date + 7;
    `);
    await gotoWhenReady(page, viewedUrl.toString(), '#roster-content');
    await openTemplatesTab(page);

    await expect(page.getByRole('status')).toContainText('Templates cannot be applied to a Published roster');
    await expect(page.getByRole('button', { name: 'Apply Lunch service' })).toBeDisabled();
    await expect(page.getByRole('button', { name: 'Apply Standard week' })).toBeDisabled();
    await expect(page.locator('[data-bepis-dropzone-ref="day-template-dropzone"]')).toHaveCount(0);
    await expect(page.locator('[data-bepis-dropzone-ref="week-template-dropzone"]')).toHaveCount(0);
});

test('saved edit conflicts preserve recovery choices', async ({ page }, testInfo) => {
    test.skip(testInfo.project.name !== 'desktop-chromium', 'Optimistic conflict acceptance is covered once on desktop.');
    await page.getByRole('button', { name: 'Edit Lunch service' }).click();
    await expect(page).toHaveURL(/ShowRosterTemplateDesigner/, { timeout: E2E_TIMEOUT.navigation });

    runSql(`
        UPDATE roster_templates
        SET current_version = current_version + 1
        WHERE name = 'Lunch service'
          AND roster_group_id = '${defaultE2ERosterGroupId}';
    `);
    await page.getByRole('button', { name: 'Save template' }).click();

    await expect(page.getByText(/This template changed elsewhere/)).toBeVisible();
    await expect(page.getByRole('button', { name: 'Reload latest' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Save as new' })).toBeVisible();
});

test('Day and Week cards converge on confirmation while controls and cancellation stay isolated @canonical-mobile', async ({ page }) => {
    const dayApply = page.getByRole('button', { name: 'Apply Lunch service' });
    await dayApply.click();
    await expect(page.getByRole('button', { name: 'Cancel', exact: true })).toBeVisible();

    await page.keyboard.press('Escape');
    await expect(page.getByRole('button', { name: 'Cancel', exact: true })).toBeHidden();

    await dayApply.click();
    await page.getByRole('tab', { name: 'Staff' }).click();
    await openTemplatesTab(page);
    await expect(page.getByRole('button', { name: 'Cancel', exact: true })).toBeHidden();

    await page.getByRole('button', { name: 'Delete Lunch service' }).click();
    await expect(page.getByRole('heading', { name: 'Delete Lunch service' })).toBeVisible();
    await expect(page.getByText('Existing rosters are unaffected')).toBeVisible();
    await gotoWhenReady(page, '/RosterWeeks', '#roster-content');
    await openTemplatesTab(page);

    await page.getByRole('button', { name: 'Apply Lunch service' }).click();
    const firstDayTarget = page.locator('[data-bepis-roster-template-day-target]').first();
    const previewResponse = page.waitForResponse((response) => response.url().includes('PreviewRosterTemplateDrop'));
    await firstDayTarget.focus();
    await page.keyboard.press('Enter');
    const previewHttpResponse = await previewResponse;
    expect(previewHttpResponse.status()).toBe(200);
    expect(await previewHttpResponse.text()).toContain('Apply Lunch service');
    await expect(page.locator('[data-bepis-roster-template-target-input]').first()).toHaveValue(/^day:/);
    await expect(page.getByRole('heading', { name: 'Apply Lunch service' })).toBeVisible();
    await page.getByRole('button', { name: 'Apply template' }).click();
    await expect(page.getByText('Template applied.')).toBeVisible();
    await gotoWhenReady(page, '/RosterWeeks', '#roster-content');
    await openTemplatesTab(page);

    const weekCard = page.getByRole('button', { name: 'Apply Standard week' }).locator('..').locator('..');
    await expect(weekCard.locator('[data-bepis-roster-template-target-input]')).toHaveValue(/^window:\d{4}-\d{2}-\d{2}$/);
    const weekPreviewResponse = page.waitForResponse((response) => response.url().includes('PreviewRosterTemplateDrop'));
    await page.getByRole('button', { name: 'Apply Standard week' }).click();
    expect((await weekPreviewResponse).status()).toBe(200);
    await expect(page.getByRole('heading', { name: 'Apply Standard week' })).toBeVisible();
    await expect(page.getByText(/replace the complete viewed week/i)).toBeVisible();
    await page.getByRole('button', { name: 'Apply template' }).click();
    await expect(page.getByText('Template applied.')).toBeVisible();
});

test('Day template keyboard targeting works in timeline mode', async ({ page }, testInfo) => {
    test.skip(testInfo.project.name !== 'desktop-chromium', 'Timeline keyboard targeting is exercised once on desktop.');
    const timelineUrl = new URL(page.url());
    timelineUrl.searchParams.set('rosterView', 'timeline');
    timelineUrl.searchParams.set('dayDate', timelineUrl.searchParams.get('anchorDate') ?? '');
    await gotoWhenReady(page, timelineUrl.toString(), '.roster-day-timeline-shell');
    await openTemplatesTab(page);

    await page.getByRole('button', { name: 'Apply Lunch service' }).click();
    let timelineDayTarget = page.locator('.roster-template-timeline-day-target [data-bepis-roster-template-day-target]');
    await expect(timelineDayTarget).toBeVisible();
    await timelineDayTarget.click();
    await expect(page.getByRole('heading', { name: 'Apply Lunch service' })).toBeVisible();

    await gotoWhenReady(page, timelineUrl.toString(), '.roster-day-timeline-shell');
    await openTemplatesTab(page);
    await page.getByRole('button', { name: 'Apply Lunch service' }).click();
    timelineDayTarget = page.locator('.roster-template-timeline-day-target [data-bepis-roster-template-day-target]');
    await timelineDayTarget.focus();
    await page.keyboard.press('Enter');
    await expect(page.getByRole('heading', { name: 'Apply Lunch service' })).toBeVisible();
});

test('Day template cards drag to compatible day targets', async ({ page }, testInfo) => {
    test.skip(testInfo.project.name !== 'desktop-chromium', 'Mouse drag is covered on desktop; touch converges through card activation.');
    const dayCard = page.locator('[data-bepis-source-ref="day-template-drag-source"]').first();
    const dayTarget = page.locator('[data-bepis-dropzone-ref="day-template-dropzone"]').first();

    const sourceBox = await dayCard.boundingBox();
    const targetBox = await dayTarget.boundingBox();
    expect(sourceBox).not.toBeNull();
    expect(targetBox).not.toBeNull();
    await page.mouse.move(sourceBox!.x + sourceBox!.width / 2, sourceBox!.y + sourceBox!.height / 2);
    await page.mouse.down();
    await page.mouse.move(targetBox!.x + targetBox!.width / 2, targetBox!.y + targetBox!.height / 2, { steps: 8 });
    await page.mouse.up();

    await expect(page.getByRole('heading', { name: 'Apply Lunch service' })).toBeVisible();
});

test('template deletion passively converges in another roster viewer', async ({ page, context }) => {
    const viewer = await context.newPage();
    await gotoWhenReady(viewer, '/RosterWeeks', '#roster-content');
    await openRoster(viewer, { email: managerEmail, useCurrentSession: true });
    await openTemplatesTab(viewer);
    await expect(viewer.getByRole('button', { name: 'Apply Lunch service' })).toBeVisible();

    await page.getByRole('button', { name: 'Delete Lunch service' }).click();
    await page.getByRole('button', { name: 'Delete template' }).click();

    await expect(viewer.getByRole('button', { name: 'Apply Lunch service' })).toHaveCount(0, { timeout: E2E_TIMEOUT.navigation });
    await viewer.close();
});
