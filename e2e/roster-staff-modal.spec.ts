import { test, expect, type BrowserContext, type Page } from '@playwright/test';
import {
    dialogMountDomAttr,
    dialogOverlayMountDomId,
    parseRosterStaffPanelSortRow,
    rosterStaffHighlightMemberDomAttr,
    rosterStaffHighlightSourceDomAttr,
    rosterStaffPanelSortRowDomAttr,
    toastOverlayMountDomId,
} from '../frontend/ts/generated/contracts';
import { gotoWhenReady, uniqueE2EValue, waitForLiveRecovery } from './support/runtime';
import { openRoster } from './support/roster';
import { runSql } from './support/database';
import { E2E_TIMEOUT } from './timeouts';

async function loginAndOpenRoster(page: Page) {
    await openRoster(page, { email: 'e2e-test@example.com' });
    await expect(page.locator('.roster-staff-panel')).toBeVisible();
}

type LiveSubscriptionWindow = Window & { __staffRemovalSubscriptionKeys?: string[] };

async function installLiveSubscriptionObserver(page: Page) {
    await page.addInitScript(() => {
        const state = window as LiveSubscriptionWindow;
        state.__staffRemovalSubscriptionKeys = [];
        document.addEventListener('app:live-update-debug', (event) => {
            const detail = (event as CustomEvent).detail;
            if (detail?.name !== 'subscription_added' || typeof detail.scopeKey !== 'string') return;
            state.__staffRemovalSubscriptionKeys?.push(detail.scopeKey);
        });
    });
}

async function waitForLiveSubscription(page: Page, scopePrefix: 'roster:' | 'timesheets:') {
    await expect.poll(
        () => page.evaluate((prefix) =>
            (window as LiveSubscriptionWindow).__staffRemovalSubscriptionKeys?.some((scopeKey) => scopeKey.startsWith(prefix)) ?? false,
        scopePrefix),
        { timeout: E2E_TIMEOUT.liveUpdate },
    ).toBe(true);
}

test.describe('Roster Staff Modal', () => {
    const restoreAlphaFixture = () => {
        runSql(`
            UPDATE staff
            SET first_name = 'Alpha', preferred_name = NULL, updated_at = NOW()
            WHERE id = 'a1000000-0000-0000-0000-000000000031';

            UPDATE roster_slots
            SET staff_id = 'a1000000-0000-0000-0000-000000000031', updated_at = NOW()
            WHERE id = 'a1000000-0000-0000-0000-000000000071';
        `);
    };
    test.beforeEach(restoreAlphaFixture);
    test.afterEach(restoreAlphaFixture);

    test('opens the dedicated trial invitation dialog without opening staff edit', async ({ page }) => {
        await loginAndOpenRoster(page);

        const initialUrl = page.url();
        const modalMount = page.locator(`#${dialogOverlayMountDomId}`);
        const trialEntry = page.locator(`[${rosterStaffPanelSortRowDomAttr}]:visible`).filter({ hasText: 'TRIAL' }).first();
        const inviteButton = trialEntry.getByRole('button', { name: /^Invite / });

        await expect(inviteButton).toBeVisible();
        await inviteButton.click();

        await expect(page).toHaveURL(initialUrl);
        await expect(modalMount.locator(`[${dialogMountDomAttr}]`)).toBeVisible();
        await expect(modalMount).toContainText('Invite trial staff');
        await expect(modalMount).not.toContainText('Edit Staff Member');
        await expect(modalMount.locator('#trial-staff-invite-form')).toBeVisible();
    });

    test('renews an expired trial invitation with a corrected fresh link', async ({ page }) => {
        const staffId = 'a1000000-0000-0000-0000-000000000035';
        const invitationId = 'a1000000-0000-0000-0000-000000000935';
        const originalEmail = `${uniqueE2EValue('expired-trial-renewal')}@example.com`;
        const correctedEmail = `${uniqueE2EValue('corrected-trial-renewal')}@example.com`;
        runSql(`
            DELETE FROM app_jobs WHERE related_table = 'venue_invitations' AND related_id = '${invitationId}';
            DELETE FROM venue_invitations WHERE staff_id = '${staffId}';
            INSERT INTO venue_invitations (id, venue_id, staff_id, email, expires_at)
            VALUES ('${invitationId}', 'a1000000-0000-0000-0000-000000000001', '${staffId}', '${originalEmail}', NOW() - INTERVAL '1 minute')
        `);

        try {
            await loginAndOpenRoster(page);
            const modalMount = page.locator(`#${dialogOverlayMountDomId}`);
            const trialEntry = page.locator(
                `[${rosterStaffPanelSortRowDomAttr}][${rosterStaffHighlightSourceDomAttr}="staff:${staffId}"]:visible`,
            );
            await trialEntry.getByRole('button', { name: /^Invite / }).click();

            await expect(modalMount).toContainText('Expired');
            const renewalForm = modalMount.locator(`form[action*="/RenewTrialStaffInvitation"]`);
            await expect(renewalForm.locator('[name="invitationEmail"]')).toHaveValue(originalEmail);
            await renewalForm.locator('[name="invitationEmail"]').fill(correctedEmail);
            await renewalForm.getByRole('button', { name: 'Renew' }).click();

            await expect(page.locator(`#${toastOverlayMountDomId}`)).toContainText(`Renewed invitation queued for ${correctedEmail} and should arrive shortly`);
            await expect(modalMount.locator(`[${dialogMountDomAttr}]`)).toHaveCount(0);

            await trialEntry.getByRole('button', { name: /^Invite / }).click();
            await expect(modalMount.getByRole('textbox', { name: 'Renewal email' })).toHaveValue(correctedEmail);
            await expect(modalMount).not.toContainText(originalEmail);
        } finally {
            runSql(`
                DELETE FROM app_jobs WHERE related_table = 'venue_invitations' AND related_id IN (
                    SELECT id FROM venue_invitations WHERE staff_id = '${staffId}'
                );
                DELETE FROM venue_invitations WHERE staff_id = '${staffId}'
            `);
        }
    });

    test('edits staff inline without navigating away from the roster', async ({ page }) => {
        await loginAndOpenRoster(page);

        const initialUrl = page.url();
        const modalMount = page.locator(`#${dialogOverlayMountDomId}`);
        const staffEntry = page.locator(
            `[${rosterStaffPanelSortRowDomAttr}][${rosterStaffHighlightSourceDomAttr}="staff:a0000000-0000-0000-0000-000000000101"]:visible`,
        );
        const pageErrors: Error[] = [];
        let blackoutRequests = 0;
        page.on('pageerror', (error) => pageErrors.push(error));
        page.on('request', (request) => {
            if (request.url().includes('/ShowVisibleUnavailabilityBlackoutsFragment')) blackoutRequests += 1;
        });
        await page.evaluate(() => {
            document.addEventListener('htmx:swapError', () => {
                document.documentElement.dataset.e2eHtmxSwapError = 'true';
            });
        });
        const blackoutResponsePromise = page.waitForResponse((response) =>
            response.url().includes('/ShowVisibleUnavailabilityBlackoutsFragment')
            && response.request().method() === 'GET',
        );
        await staffEntry.click();

        await expect(page).toHaveURL(initialUrl);
        await expect(modalMount.locator(`[${dialogMountDomAttr}]`)).toBeVisible();
        await expect(modalMount).toContainText('Edit Staff Member');
        await blackoutResponsePromise;
        await waitForLiveRecovery(page);
        expect(blackoutRequests).toBe(1);
        expect(pageErrors).toEqual([]);
        await expect(page.locator('html')).not.toHaveAttribute('data-e2e-htmx-swap-error', 'true');
        await modalMount.getByRole('button', { name: 'Profile Details', exact: true }).click();

        const staffEditForm = modalMount.locator('#staff-edit-form:visible');
        await expect(staffEditForm).toBeVisible();
        await expect(staffEditForm.getByText('Roster Groups', { exact: true })).toHaveCount(0);
        await expect(staffEditForm.locator('input[type="hidden"][name="rosterGroupIds"]')).toHaveValue('a1000000-0000-0000-0000-000000000211');
        const firstNameField = staffEditForm.locator('#firstName');
        const lastNameField = staffEditForm.locator('#lastName');
        const formAction = await staffEditForm.getAttribute('action');

        const validationResponse = await page.evaluate(
            async ({ action }) => {
                const form = document.querySelector<HTMLFormElement>('#staff-edit-form');
                if (form === null) throw new Error('Expected visible staff edit form');

                const body = new URLSearchParams();
                new FormData(form).forEach((value, key) => {
                    if (typeof value === 'string') body.append(key, value);
                });
                body.set('firstName', '');

                const response = await fetch(action, {
                    method: 'POST',
                    headers: {
                        'HX-Request': 'true',
                        'Content-Type': 'application/x-www-form-urlencoded',
                    },
                    body: body.toString(),
                });

                return await response.text();
            },
            { action: formAction ?? '' },
        );

        expect(validationResponse).toContain('Edit Staff Member');
        expect(validationResponse).toContain('This field cannot be empty');
        expect(validationResponse).not.toContain('Roster App');

        await firstNameField.fill('Roster');
        await lastNameField.fill('Modal Spec');
        const profileRefreshPromise = page.waitForResponse((response) => {
            const url = new URL(response.url());
            return url.pathname.includes('/ShowStaffContentLiveFragment') && url.searchParams.get('section') === 'profile';
        });
        const preferencesRefreshPromise = page.waitForResponse((response) => {
            const url = new URL(response.url());
            return url.pathname.includes('/ShowStaffContentLiveFragment') && url.searchParams.get('section') === 'preferences';
        });
        await modalMount.getByRole('button', { name: 'Save' }).click();
        const [profileRefresh, preferencesRefresh] = await Promise.all([profileRefreshPromise, preferencesRefreshPromise]);
        await Promise.all([profileRefresh.finished(), preferencesRefresh.finished()]);

        await expect(page).toHaveURL(initialUrl);
        await expect(modalMount.locator('[data-bepis-surface="staff"]')).toBeVisible();
        await expect(modalMount.locator('#staff-profile-details')).toBeVisible();
        await expect(modalMount.locator('#staff-edit-form #firstName')).toHaveValue('Roster');
        await expect(page.locator(`#${toastOverlayMountDomId}`)).toContainText('Staff member updated');

        await modalMount.getByRole('button', { name: 'Shift Preferences', exact: true }).click();
        const preferenceForm = modalMount.locator('#staff-shift-preferences-form');
        await expect(preferenceForm).toBeVisible();
        await expect(preferenceForm.locator('button[type="submit"]')).toHaveCount(0);
        const preferenceResponsePromise = page.waitForResponse((response) =>
            response.request().method() === 'POST' && response.url().includes('/UpdateStaff'),
        );
        await preferenceForm.evaluate((form) => {
            const checkbox = form.querySelector<HTMLInputElement>('input[type="checkbox"]');
            if (!checkbox) throw new Error('Missing staff shift-preference availability input');
            checkbox.click();
        });
        const preferenceResponse = await preferenceResponsePromise;
        expect(preferenceResponse.status(), await preferenceResponse.text()).toBe(200);
        await preferenceResponse.finished();
        await expect(modalMount.locator('#staff-profile-preferences')).toBeVisible();
        await expect(page.locator(`#${toastOverlayMountDomId}`)).toContainText('Shift preferences updated');

    });

    test('admin pay remediation removes the staff-panel error pill without a reload', async ({ page }) => {
        test.setTimeout(E2E_TIMEOUT.slowTest);
        const staffId = 'a1000000-0000-0000-0000-000000000031';
        const awardLevelId = 'a1000000-0000-0000-0000-000000000111';
        runSql(`
            UPDATE staff
            SET pay_assignment_mode = 'legacy_unresolved',
                default_award_level_id = NULL,
                imported_xero_pay_item_id = NULL
            WHERE id = '${staffId}'
        `);

        try {
            await openRoster(page, { email: 'e2e-admin@example.com' });

            const modalMount = page.locator(`#${dialogOverlayMountDomId}`);
            const staffEntry = page.locator(
                `[${rosterStaffPanelSortRowDomAttr}][${rosterStaffHighlightSourceDomAttr}="staff:${staffId}"]:visible`,
            );
            await expect(staffEntry.locator('[aria-label^="Pay configuration required"]')).toBeVisible();
            await staffEntry.click();
            await modalMount.getByRole('button', { name: 'Profile Details', exact: true }).click();

            const staffEditForm = modalMount.locator('#staff-edit-form:visible');
            await staffEditForm.locator('#payRateSelection').selectOption(`award:${awardLevelId}`);
            const updateResponsePromise = page.waitForResponse((response) => response.request().method() === 'POST' && response.url().includes('/UpdateStaff'));
            const staffListRefreshPromise = page.waitForResponse((response) => response.request().method() === 'GET' && response.url().includes('/ShowRosterWeekStaffPanelFragment'));
            await staffEditForm.getByRole('button', { name: 'Save profile details' }).click();
            const updateResponse = await updateResponsePromise;
            expect(updateResponse.headers()['hx-trigger']).toContain('roster-staff-panel');
            await (await staffListRefreshPromise).finished();

            await expect(page.locator(`#${toastOverlayMountDomId}`)).toContainText('Staff member updated');
            await expect(staffEntry.locator('[aria-label^="Pay configuration required"]')).toHaveCount(0);
        } finally {
            runSql(`
                UPDATE staff
                SET pay_assignment_mode = 'award_rate',
                    default_award_level_id = '${awardLevelId}',
                    imported_xero_pay_item_id = NULL
                WHERE id = '${staffId}'
            `);
        }
    });

    test('admin profile save refreshes an assigned roster staff name and exposes the venue role control', async ({ page }) => {
        await openRoster(page, { email: 'e2e-admin@example.com' });

        const modalMount = page.locator(`#${dialogOverlayMountDomId}`);
        const staffPanel = page.locator('.roster-staff-panel');
        const rosterGrid = page.locator('.roster-grid-frame');
        const assignedStaffKey = 'staff:a1000000-0000-0000-0000-000000000031';
        await expect(rosterGrid.locator(`[${rosterStaffHighlightMemberDomAttr}="${assignedStaffKey}"]`).first()).toBeVisible();
        const assignedEntry = staffPanel.locator(
            `[${rosterStaffPanelSortRowDomAttr}][${rosterStaffHighlightSourceDomAttr}="${assignedStaffKey}"]`,
        );
        const assignedPayload = await assignedEntry.getAttribute(rosterStaffPanelSortRowDomAttr);
        expect(assignedPayload).toBeTruthy();
        const assignedStaffName = parseRosterStaffPanelSortRow(JSON.parse(assignedPayload ?? 'null') as unknown).staffName;
        await expect(assignedEntry).toBeVisible();
        await expect(rosterGrid).toContainText(assignedStaffName);
        await assignedEntry.click();

        await modalMount.getByRole('button', { name: 'Profile Details', exact: true }).click();
        const staffEditForm = modalMount.locator('#staff-edit-form:visible');
        const venueRole = staffEditForm.locator('#venueRole');
        await expect(venueRole).toBeVisible();
        await expect(venueRole.getByRole('option', { name: 'Manager' })).toHaveCount(1);

        await staffEditForm.locator('#firstName').fill('Alphonso');
        const rosterSwapsPromise = page.evaluate(() => new Promise<void>((resolve) => {
            const pendingTargets = new Set(['roster-slots-grid', 'roster-staff-panel-fragment']);
            document.addEventListener('app:live-update-performance', (event) => {
                const detail = (event as CustomEvent<Record<string, unknown>>).detail;
                if (detail?.name !== 'live_updates.swap_fragment' || detail?.outcome !== 'swapped' || typeof detail?.targetId !== 'string') return;
                pendingTargets.delete(detail.targetId);
                if (pendingTargets.size === 0) resolve();
            });
        }));
        const updateResponsePromise = page.waitForResponse((response) => response.request().method() === 'POST' && response.url().includes('/UpdateStaff'));
        const rosterRefreshPromise = page.waitForResponse((response) => response.request().method() === 'GET' && response.url().includes('/ShowRosterWeekSlotsGridFragment'));
        const staffListRefreshPromise = page.waitForResponse((response) => response.request().method() === 'GET' && response.url().includes('/ShowRosterWeekStaffPanelFragment'));
        await staffEditForm.getByRole('button', { name: 'Save profile details' }).click();
        const updateResponse = await updateResponsePromise;
        expect(updateResponse.headers()['hx-trigger']).not.toContain('roster-content');
        expect(updateResponse.headers()['hx-trigger']).toContain('roster-slots-grid');
        const rosterRefreshResponse = await rosterRefreshPromise;
        const staffListRefreshResponse = await staffListRefreshPromise;
        await Promise.all([rosterRefreshResponse.finished(), staffListRefreshResponse.finished()]);
        await rosterSwapsPromise;

        await expect(page.locator(`#${toastOverlayMountDomId}`)).toContainText('Staff member updated');
        await expect(assignedEntry).toContainText('Alphonso');
        await expect(rosterGrid).toContainText('Alphonso');
    });

    test('removing staff refreshes actor and passive roster views', async ({ browser }) => {
        test.setTimeout(E2E_TIMEOUT.slowTest);
        const userId = globalThis.crypto.randomUUID();
        const membershipId = globalThis.crypto.randomUUID();
        const staffId = globalThis.crypto.randomUUID();
        const staffRosterGroupId = globalThis.crypto.randomUUID();
        const rosterSlotId = globalThis.crypto.randomUUID();
        const userEmail = `e2e-staff-removal-${userId}@example.com`;
        const contexts: BrowserContext[] = [];
        try {
            runSql(`
            CREATE TEMP TABLE e2e_staff_removal_operational_day AS
            SELECT CASE
                WHEN (CURRENT_TIMESTAMP AT TIME ZONE timezone)::time < TIME '06:00'
                    THEN (CURRENT_TIMESTAMP AT TIME ZONE timezone)::date - 1
                ELSE (CURRENT_TIMESTAMP AT TIME ZONE timezone)::date
            END AS operational_day
            FROM venue_config
            WHERE venue_id = 'a1000000-0000-0000-0000-000000000001';
            INSERT INTO users (id, email, password_hash, user_role, is_profile_completed, email_verified_at)
            SELECT '${userId}', '${userEmail}', password_hash, 'staff', TRUE, NOW()
            FROM users WHERE email = 'e2e-worker@example.com';
            INSERT INTO venue_memberships (id, venue_id, user_id, venue_role, is_active)
            VALUES ('${membershipId}', 'a1000000-0000-0000-0000-000000000001', '${userId}', 'worker', TRUE);
            INSERT INTO staff (
                id, venue_id, user_id, first_name, last_name, phone,
                emergency_contact_name, emergency_contact_phone,
                ideal_shifts_per_week, employment_basis, pay_assignment_mode,
                default_award_level_id, is_active
            ) VALUES (
                '${staffId}', 'a1000000-0000-0000-0000-000000000001', '${userId}', 'Remove', 'Live', '0400000991',
                'Removal Contact', '0400000992', 0, 'permanent', 'award_rate',
                'a1000000-0000-0000-0000-000000000111', TRUE
            );
            INSERT INTO staff_roster_groups (id, staff_id, roster_group_id)
            VALUES ('${staffRosterGroupId}', '${staffId}', 'a1000000-0000-0000-0000-000000000211');
            INSERT INTO roster_days (venue_id, roster_group_id, operational_date, publication_state, is_closed, row_count)
            SELECT
                'a1000000-0000-0000-0000-000000000001',
                'a1000000-0000-0000-0000-000000000211',
                CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + day_index,
                'published', FALSE, 2
            FROM generate_series(0, 6) AS day_index
            ON CONFLICT (roster_group_id, operational_date) DO UPDATE SET publication_state = 'published';
            INSERT INTO roster_lanes (roster_day_id, name, sort_order)
            SELECT roster_days.id, 'Early', 0
            FROM roster_days
            WHERE roster_days.roster_group_id = 'a1000000-0000-0000-0000-000000000211'
              AND roster_days.operational_date BETWEEN CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)
                  AND CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 6
              AND NOT EXISTS (
                  SELECT 1 FROM roster_lanes
                  WHERE roster_lanes.roster_day_id = roster_days.id
                    AND roster_lanes.deleted_at IS NULL
              );
            UPDATE roster_days SET publication_state = 'published'
            FROM e2e_staff_removal_operational_day
            WHERE roster_days.roster_group_id = 'a1000000-0000-0000-0000-000000000211'
              AND roster_days.operational_date = e2e_staff_removal_operational_day.operational_day;
            WITH target_day AS (
                SELECT roster_days.id
                FROM roster_days, e2e_staff_removal_operational_day
                WHERE roster_days.roster_group_id = 'a1000000-0000-0000-0000-000000000211'
                  AND roster_days.operational_date = e2e_staff_removal_operational_day.operational_day
            ), target_cell AS (
                SELECT target_day.id AS roster_day_id, COALESCE(MAX(roster_slots.row_index), -1) + 1 AS row_index
                FROM target_day
                LEFT JOIN roster_slots ON roster_slots.roster_day_id = target_day.id AND roster_slots.deleted_at IS NULL
                GROUP BY target_day.id
            )
            INSERT INTO roster_slots (
                id, roster_day_id, roster_lane_id, staff_id, assignment_state,
                row_index, starts_at, ends_at, timezone, shift_type_id
            )
            SELECT
                '${rosterSlotId}', target_cell.roster_day_id,
                (SELECT roster_lanes.id FROM roster_lanes WHERE roster_lanes.roster_day_id = target_cell.roster_day_id AND roster_lanes.deleted_at IS NULL ORDER BY roster_lanes.sort_order, roster_lanes.id LIMIT 1),
                '${staffId}', 'staff', target_cell.row_index,
                (operational_day + TIME '12:00') AT TIME ZONE 'Australia/Melbourne',
                (operational_day + TIME '16:00') AT TIME ZONE 'Australia/Melbourne',
                'Australia/Melbourne', 'a1000000-0000-0000-0000-000000000133'
            FROM target_cell, e2e_staff_removal_operational_day;
            UPDATE roster_days
            SET row_count = GREATEST(row_count, roster_slots.row_index + 1)
            FROM roster_slots
            WHERE roster_slots.id = '${rosterSlotId}' AND roster_days.id = roster_slots.roster_day_id;
        `);

        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        contexts.push(actorContext, viewerContext);
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();
        await Promise.all([
            installLiveSubscriptionObserver(actorPage),
            installLiveSubscriptionObserver(viewerPage),
        ]);
        const staffSelector = `[${rosterStaffPanelSortRowDomAttr}][${rosterStaffHighlightSourceDomAttr}="staff:${staffId}"]:visible`;

            await openRoster(actorPage, { email: 'e2e-admin@example.com' });
            await openRoster(viewerPage, { email: 'e2e-admin@example.com' });
            const rosterPath = '/RosterWeeks?rosterGroupId=a1000000-0000-0000-0000-000000000211';
            await gotoWhenReady(actorPage, rosterPath, '#roster-week-shell');
            await gotoWhenReady(viewerPage, rosterPath, '#roster-week-shell');
            await Promise.all([
                waitForLiveSubscription(actorPage, 'roster:'),
                waitForLiveSubscription(viewerPage, 'roster:'),
            ]);
            await expect(actorPage.locator(staffSelector)).toBeVisible();
            await expect(viewerPage.locator(staffSelector)).toBeVisible();
            await expect(viewerPage.locator('.roster-grid-frame')).toContainText('Remove');
            const modalMount = actorPage.locator(`#${dialogOverlayMountDomId}`);
            await actorPage.locator(staffSelector).click();
            await modalMount.getByRole('button', { name: 'Profile Details', exact: true }).click();
            await modalMount.getByRole('link', { name: 'Remove staff member' }).click();

            await expect(modalMount.getByRole('heading', { name: 'Remove staff member' })).toBeVisible();
            await expect(modalMount).toContainText('Are you sure you want to remove this staff member? This cannot be undone.');
            await modalMount.getByRole('button', { name: 'Remove staff member' }).click();

            await expect(actorPage.locator(`#${toastOverlayMountDomId}`)).toContainText('Staff member removed');
            await expect(modalMount.locator(`[${dialogMountDomAttr}]`)).toHaveCount(0);
            await expect(actorPage.locator(staffSelector)).toHaveCount(0, { timeout: E2E_TIMEOUT.liveUpdate });
            await expect(viewerPage.locator(staffSelector)).toHaveCount(0, { timeout: E2E_TIMEOUT.liveUpdate });
            await expect(viewerPage.locator('.roster-grid-frame')).not.toContainText('Remove', { timeout: E2E_TIMEOUT.liveUpdate });
        } finally {
            await Promise.allSettled(contexts.map((context) => context.close()));
            runSql(`
                BEGIN;
                SET LOCAL ihp_roster.allow_hard_delete = 'on';
                UPDATE roster_days SET publication_state = 'draft'
                WHERE id = (SELECT roster_day_id FROM roster_slots WHERE id = '${rosterSlotId}');
                DELETE FROM roster_slots WHERE id = '${rosterSlotId}';
                DELETE FROM staff_roster_groups WHERE id = '${staffRosterGroupId}';
                DELETE FROM venue_memberships WHERE id = '${membershipId}';
                DELETE FROM staff WHERE id = '${staffId}';
                DELETE FROM users WHERE id = '${userId}';
                UPDATE roster_days SET publication_state = 'draft'
                WHERE roster_group_id = 'a1000000-0000-0000-0000-000000000211'
                  AND operational_date BETWEEN CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)
                      AND CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 6;
                COMMIT;
            `);
        }
    });
});
