import { expect, test, type Locator } from '@playwright/test';
import { E2E_TIMEOUT, gotoWhenReady, openAdminWithSeededPasskeySession, querySql, runSql } from './test-helpers';

const venueId = 'a1000000-0000-0000-0000-000000000001';
const fixtureGroupId = 'd2000000-0000-0000-0000-000000000001';

function seedRegroupingFixture() {
    runSql(`
        INSERT INTO roster_groups (id, venue_id, name, sort_order, is_active, is_default)
        VALUES ('${fixtureGroupId}', '${venueId}', 'Window start E2E', 900, TRUE, FALSE)
        ON CONFLICT (id) DO UPDATE SET archived_at = NULL, is_active = TRUE;

        INSERT INTO roster_days (id, venue_id, roster_group_id, operational_date, publication_state, day_offset)
        VALUES
            ('d2000000-0000-0000-0000-000000000011', '${venueId}', '${fixtureGroupId}', '2099-01-05', 'published', 0),
            ('d2000000-0000-0000-0000-000000000012', '${venueId}', '${fixtureGroupId}', '2099-01-06', 'published', 1),
            ('d2000000-0000-0000-0000-000000000013', '${venueId}', '${fixtureGroupId}', '2099-01-07', 'published', 2),
            ('d2000000-0000-0000-0000-000000000014', '${venueId}', '${fixtureGroupId}', '2099-01-08', 'published', 3),
            ('d2000000-0000-0000-0000-000000000015', '${venueId}', '${fixtureGroupId}', '2099-01-09', 'published', 4),
            ('d2000000-0000-0000-0000-000000000016', '${venueId}', '${fixtureGroupId}', '2099-01-10', 'published', 5),
            ('d2000000-0000-0000-0000-000000000017', '${venueId}', '${fixtureGroupId}', '2099-01-11', 'published', 6),
            ('d2000000-0000-0000-0000-000000000018', '${venueId}', '${fixtureGroupId}', '2099-01-12', 'published', 0)
        ON CONFLICT (roster_group_id, operational_date) DO UPDATE SET publication_state = 'published';
    `);
}

async function submitConfirmation(confirmation: Locator) {
    await confirmation.evaluate((form) => {
        if (!(form instanceof HTMLFormElement)) throw new Error('Expected the roster window start-day confirmation form');
        form.requestSubmit();
    });
}

function fixturePublicationStates() {
    return querySql(`
        SELECT string_agg(publication_state::text, ',' ORDER BY operational_date)
        FROM roster_days
        WHERE roster_group_id = '${fixtureGroupId}'
          AND operational_date BETWEEN '2099-01-05' AND '2099-01-12'
    `);
}

test.describe('Roster window start day setting', () => {
    test.describe.configure({ retries: 0, timeout: E2E_TIMEOUT.slowTest });

    test('previews regrouping, confirms Draft normalization, and never restores publication', async ({ page }) => {
        const originalPublishedIds: string[] = querySql(`SELECT id FROM roster_days WHERE venue_id = '${venueId}' AND publication_state = 'published'`).split('\n').filter(Boolean);
        const [originalStartDay, originalEpoch, originalRevision] = querySql(`SELECT roster_week_starts_on || '|' || week_offset_epoch || '|' || roster_calendar_revision FROM venue_config WHERE venue_id = '${venueId}'`).split('|');

        try {
            runSql(`UPDATE venue_config SET roster_week_starts_on = 1, week_offset_epoch = DATE '2025-01-06' WHERE venue_id = '${venueId}'`);
            seedRegroupingFixture();

            await openAdminWithSeededPasskeySession(page);
            await page.getByRole('button', { name: 'Venue Settings' }).click();

            const setting = page.locator('.admin-setting-row', { hasText: 'Roster window start day' });
            await setting.locator('select[name="rosterWeekStartsOn"]').selectOption('2');
            await setting.getByRole('button', { name: 'Preview impact' }).click();

            const confirmation = page.locator('.admin-setting-row', { hasText: 'Confirm roster window start day' });
            await expect(confirmation).toBeVisible();
            await expect(confirmation).toContainText('Tuesday');
            await expect(confirmation).toContainText('Mixed Published windows');
            expect(fixturePublicationStates()).toBe('published,published,published,published,published,published,published,published');

            await submitConfirmation(confirmation);
            await expect(page.locator('.admin-setting-row', { hasText: 'Roster window start day' })).toBeVisible();
            expect(querySql(`SELECT roster_week_starts_on FROM venue_config WHERE venue_id = '${venueId}'`)).toBe('2');
            expect(fixturePublicationStates()).toBe('draft,published,published,published,published,published,published,published');

            await gotoWhenReady(
                page,
                `/ShowRosterWindow?anchorDate=2099-01-07&rosterGroupId=${fixtureGroupId}`,
                '#roster-week-shell',
            );
            await expect(page.locator('.roster-day-date').first()).toHaveText('Tue 06/01');

            await gotoWhenReady(
                page,
                `/ShowRosterWindow?anchorDate=2099-01-07&rosterGroupId=${fixtureGroupId}&rosterView=timeline&dayDate=2099-01-06`,
                '.roster-day-timeline-shell',
            );
            await expect(page.locator('.roster-day-timeline')).toHaveAttribute('aria-label', 'Tuesday 06/01 roster timeline');

            await page.getByRole('link', { name: 'admin' }).click();
            await page.getByRole('button', { name: 'Venue Settings' }).click();
            await page.setViewportSize({ width: 390, height: 844 });
            const restoredSetting = page.locator('.admin-setting-row', { hasText: 'Roster window start day' });
            await restoredSetting.locator('select[name="rosterWeekStartsOn"]').selectOption('1');
            await restoredSetting.getByRole('button', { name: 'Preview impact' }).click();
            const mobileConfirmation = page.locator('.admin-setting-row', { hasText: 'Confirm roster window start day' });
            await expect(mobileConfirmation).toBeVisible();
            await expect(mobileConfirmation.getByRole('button', { name: 'Confirm change' })).toBeVisible();
            await submitConfirmation(mobileConfirmation);

            expect(fixturePublicationStates()).toBe('draft,draft,draft,draft,draft,draft,draft,draft');
        } finally {
            runSql(`
                BEGIN;
                UPDATE roster_days SET publication_state = 'draft' WHERE venue_id = '${venueId}';
                ${originalPublishedIds.length > 0 ? `UPDATE roster_days SET publication_state = 'published' WHERE id IN (${originalPublishedIds.map((id) => `'${id}'`).join(',')});` : ''}
                UPDATE roster_groups SET is_active = FALSE WHERE id = '${fixtureGroupId}';
                ALTER TABLE venue_config DISABLE TRIGGER advance_roster_calendar_revision;
                UPDATE venue_config
                SET roster_week_starts_on = ${Number(originalStartDay)},
                    week_offset_epoch = DATE '${originalEpoch}',
                    roster_calendar_revision = ${Number(originalRevision)}
                WHERE venue_id = '${venueId}';
                ALTER TABLE venue_config ENABLE TRIGGER advance_roster_calendar_revision;
                COMMIT;
            `);
        }
    });
});
