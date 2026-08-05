import { expect, test } from '@playwright/test';
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

function resetTemplateDesignerState() {
    runSql(`
        TRUNCATE roster_template_shifts, roster_template_columns, roster_template_days,
            roster_template_designs, roster_templates;
    `);
}

async function openTemplateCreation(page: Parameters<typeof gotoWhenReady>[0]) {
    await gotoWhenReady(
        page,
        `/NewRosterTemplate?rosterGroupId=${defaultE2ERosterGroupId}`,
        '#roster-template-create',
    );
}

test.beforeEach(async ({ page }) => {
    resetTemplateDesignerState();
    runSql(`
        INSERT INTO roster_days (roster_week_id, day_offset)
        SELECT roster_weeks.id, offsets.day_offset
        FROM roster_weeks
        CROSS JOIN generate_series(0, 6) AS offsets(day_offset)
        WHERE roster_weeks.roster_group_id = '${defaultE2ERosterGroupId}'
          AND roster_weeks.week_offset = 0
          AND roster_weeks.archived_at IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM roster_days
              WHERE roster_days.roster_week_id = roster_weeks.id
                AND roster_days.day_offset = offsets.day_offset
          );
    `);
    await loginAs(page, managerEmail, password);
});

test('blank design opens in the roster card and occupied work remains recoverable', async ({ page }) => {
    await openRoster(page, { email: managerEmail, useCurrentSession: true });
    await page.getByRole('tab', { name: 'Templates' }).click();
    await page.getByRole('link', { name: 'New' }).click();
    await expect(page.locator('#roster-template-create')).toBeVisible();
    await page.getByRole('radio', { name: 'Week', exact: true }).check();
    await page.getByLabel('Template name').fill('e2e blank week');
    await page.getByLabel(/Start from a blank design/).check();
    await page.getByRole('button', { name: 'Continue' }).click();

    await expect(page).toHaveURL(/ShowRosterTemplateDesigner/, { timeout: E2E_TIMEOUT.navigation });
    await expect(page.locator('#roster-template-designer .roster-main-panel')).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Template design', exact: true })).toBeVisible();
    await expect(page.getByText('Week template · Private draft · Autosaved')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Add shift' }).first()).toBeVisible();
    await expect(page.getByRole('button', { name: 'Save template' })).toBeVisible();

    await openTemplateCreation(page);
    await page.getByRole('radio', { name: 'Day', exact: true }).check();
    await page.getByLabel('Template name').fill('e2e replacement day');
    await page.getByLabel(/Start from a blank design/).check();
    await page.getByRole('button', { name: 'Continue' }).click();

    await expect(page.getByRole('heading', { name: 'A template draft is already in progress' })).toBeVisible();
    await expect(page.getByRole('link', { name: 'Continue draft' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Discard and start new' })).toBeVisible();
    await expect(page.getByRole('link', { name: 'Cancel' })).toBeVisible();

    await page.getByRole('link', { name: 'Continue draft' }).click();
    await expect(page.getByText('e2e blank week', { exact: true })).toBeVisible();

    await openTemplateCreation(page);
    await page.getByRole('radio', { name: 'Day', exact: true }).check();
    await page.getByLabel('Template name').fill('e2e replacement day');
    await page.getByLabel(/Start from a blank design/).check();
    await page.getByRole('button', { name: 'Continue' }).click();
    await page.getByRole('button', { name: 'Discard and start new' }).click();

    await expect(page).toHaveURL(/ShowRosterTemplateDesigner/, { timeout: E2E_TIMEOUT.navigation });
    await expect(page.getByText('e2e replacement day', { exact: true })).toBeVisible();
    await expect(page.getByText('Day template · Private draft · Autosaved')).toBeVisible();
});

test('complete Week references open an isolated prefilled designer', async ({ page }, testInfo) => {
    test.skip(testInfo.project.name !== 'desktop-chromium', 'Week reference acceptance is covered once on desktop.');
    await openTemplateCreation(page);
    await page.getByRole('radio', { name: 'Week', exact: true }).check();
    await page.getByLabel('Template name').fill('e2e week reference');
    await page.getByLabel(/Use a roster as reference/).check();
    await page.getByRole('button', { name: 'Continue' }).click();

    await expect(page.getByRole('heading', { name: 'Select a reference week' })).toBeVisible();
    await page.getByRole('button', { name: /Use this week as template reference/ }).click();
    await expect(page.getByRole('heading', { name: 'Confirm reference' })).toBeVisible();
    await page.getByRole('button', { name: 'Open prefilled designer' }).click();

    await expect(page).toHaveURL(/ShowRosterTemplateDesigner/, { timeout: E2E_TIMEOUT.navigation });
    await expect(page.getByText('e2e week reference', { exact: true })).toBeVisible();
    await expect(page.getByText('Week template · Private draft · Autosaved')).toBeVisible();
});

test('reference selection is keyboard and touch operable before confirmation @canonical-mobile', async ({ page }, testInfo) => {
    const isMobile = Boolean(testInfo.project.use.isMobile);
    await openTemplateCreation(page);
    await page.getByRole('radio', { name: 'Day', exact: true }).check();
    await page.getByLabel('Template name').fill('e2e Monday reference');
    await page.getByLabel(/Use a roster as reference/).check();
    await page.getByRole('button', { name: 'Continue' }).click();

    await expect(page).toHaveURL(/ShowRosterTemplateReference/, { timeout: E2E_TIMEOUT.navigation });
    await expect(page.getByRole('heading', { name: 'Select a reference day' })).toBeVisible();
    if (isMobile) {
        await expect(page.getByText('Tap a valid outlined day or week to select it.')).toBeVisible();
    }

    const monday = page.getByRole('button', { name: /Use Monday as template reference/ });
    const target = monday.locator('xpath=ancestor::form[1]');
    const beforeFocus = await target.evaluate((element) => getComputedStyle(element).borderTopColor);
    await monday.focus();
    await expect(monday).toBeFocused();
    await expect.poll(
        () => target.evaluate((element) => getComputedStyle(element).borderTopColor),
        { timeout: E2E_TIMEOUT.action },
    ).not.toBe(beforeFocus);
    await monday.click();

    await expect(page.getByRole('heading', { name: 'Confirm reference' })).toBeVisible();
    await expect(page.getByText('No roster data will be changed', { exact: false })).toBeVisible();
    await page.getByRole('button', { name: 'Open prefilled designer' }).click();

    await expect(page).toHaveURL(/ShowRosterTemplateDesigner/, { timeout: E2E_TIMEOUT.navigation });
    await expect(page.getByText('e2e Monday reference', { exact: true })).toBeVisible();
    await expect(page.getByText('Day template · Private draft · Autosaved')).toBeVisible();
});
