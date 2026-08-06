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
import { gotoWhenReady, openRoster, runSql, uniqueE2EValue } from './test-helpers';
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

            await expect(page.locator(`#${toastOverlayMountDomId}`)).toContainText(`Invitation renewed for ${correctedEmail}`);
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
        await staffEntry.click();

        await expect(page).toHaveURL(initialUrl);
        await expect(modalMount.locator(`[${dialogMountDomAttr}]`)).toBeVisible();
        await expect(modalMount).toContainText('Edit Staff Member');
        await modalMount.getByRole('button', { name: 'Profile Details' }).click();

        const staffEditForm = modalMount.locator('#staff-edit-form:visible');
        await expect(staffEditForm).toBeVisible();
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
        await modalMount.getByRole('button', { name: 'Save' }).click();

        await expect(page).toHaveURL(initialUrl);
        await expect(modalMount.locator('[data-bepis-surface="staff"]')).toBeVisible();
        await expect(modalMount.locator('#staff-profile-details')).toBeVisible();
        await expect(modalMount.locator('#staff-edit-form #firstName')).toHaveValue('Roster');
        await expect(page.locator(`#${toastOverlayMountDomId}`)).toContainText('Staff member updated');

        await modalMount.getByRole('button', { name: 'Shift Preferences', exact: true }).click();
        await expect(modalMount.locator('#staff-shift-preferences-form')).toBeVisible();
        await modalMount.locator('#staff-shift-preferences-form button[type="submit"]').click();
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
            await modalMount.getByRole('button', { name: 'Profile Details' }).click();

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

        await modalMount.getByRole('button', { name: 'Profile Details' }).click();
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
        const rosterDayId = 'a1000000-0000-0000-0000-000000000994';
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
            INSERT INTO roster_days (id, roster_week_id, day_offset, is_closed, row_count)
            VALUES ('${rosterDayId}', 'a1000000-0000-0000-0000-000000000051', (SELECT EXTRACT(ISODOW FROM operational_day)::int - 1 FROM e2e_staff_removal_operational_day), FALSE, 1)
            ON CONFLICT (id) DO UPDATE SET is_closed = FALSE, row_count = 1, updated_at = NOW();
            UPDATE roster_weeks SET is_live = TRUE WHERE id = 'a1000000-0000-0000-0000-000000000051';
            INSERT INTO roster_slots (
                id, roster_day_id, staff_id, assignment_state, roster_week_slot_definition_id,
                row_index, starts_at, ends_at, timezone, shift_type_id
            ) VALUES (
                '${rosterSlotId}', '${rosterDayId}', '${staffId}', 'staff',
                'a1000000-0000-0000-0000-000000000081', 0,
                ((SELECT operational_day FROM e2e_staff_removal_operational_day) + TIME '12:00') AT TIME ZONE 'Australia/Melbourne',
                ((SELECT operational_day FROM e2e_staff_removal_operational_day) + TIME '16:00') AT TIME ZONE 'Australia/Melbourne',
                'Australia/Melbourne', 'a1000000-0000-0000-0000-000000000133'
            );
        `);

        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const timesheetContext = await browser.newContext();
        contexts.push(actorContext, viewerContext, timesheetContext);
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();
        const timesheetPage = await timesheetContext.newPage();
        await Promise.all([
            installLiveSubscriptionObserver(actorPage),
            installLiveSubscriptionObserver(viewerPage),
            installLiveSubscriptionObserver(timesheetPage),
        ]);
        const staffSelector = `[${rosterStaffPanelSortRowDomAttr}][${rosterStaffHighlightSourceDomAttr}="staff:${staffId}"]:visible`;

            await openRoster(actorPage, { email: 'e2e-admin@example.com' });
            await openRoster(viewerPage, { email: 'e2e-admin@example.com' });
            await openRoster(timesheetPage, { email: 'e2e-admin@example.com' });
            const rosterPath = '/ShowRosterWeek?weekOffset=0&rosterGroupId=a1000000-0000-0000-0000-000000000211';
            await gotoWhenReady(actorPage, rosterPath, '#roster-week-shell');
            await gotoWhenReady(viewerPage, rosterPath, '#roster-week-shell');
            await gotoWhenReady(timesheetPage, '/Timesheets?weekOffset=0&showApproved=true&showAllStaff=true&showSuggestions=true', '#timesheet-week-shell');
            await Promise.all([
                waitForLiveSubscription(actorPage, 'roster:'),
                waitForLiveSubscription(viewerPage, 'roster:'),
                waitForLiveSubscription(timesheetPage, 'timesheets:'),
            ]);
            await expect(actorPage.locator(staffSelector)).toBeVisible();
            await expect(viewerPage.locator(staffSelector)).toBeVisible();
            await expect(viewerPage.locator('.roster-grid-frame')).toContainText('Remove');
            const timesheetSuggestion = timesheetPage.locator(`.timesheet-suggestion-card[data-timesheet-suggestion-id="${rosterSlotId}"]`);
            await expect(timesheetSuggestion).toHaveCount(1);

            const modalMount = actorPage.locator(`#${dialogOverlayMountDomId}`);
            await actorPage.locator(staffSelector).click();
            await modalMount.getByRole('button', { name: 'Profile Details' }).click();
            await modalMount.getByRole('link', { name: 'Remove staff member' }).click();

            await expect(modalMount.getByRole('heading', { name: 'Remove staff member' })).toBeVisible();
            await expect(modalMount).toContainText('Are you sure you want to remove this staff member? This cannot be undone.');
            await modalMount.getByRole('button', { name: 'Remove staff member' }).click();

            await expect(actorPage.locator(`#${toastOverlayMountDomId}`)).toContainText('Staff member removed');
            await expect(modalMount.locator(`[${dialogMountDomAttr}]`)).toHaveCount(0);
            await expect(actorPage.locator(staffSelector)).toHaveCount(0, { timeout: E2E_TIMEOUT.liveUpdate });
            await expect(viewerPage.locator(staffSelector)).toHaveCount(0, { timeout: E2E_TIMEOUT.liveUpdate });
            await expect(viewerPage.locator('.roster-grid-frame')).not.toContainText('Remove', { timeout: E2E_TIMEOUT.liveUpdate });
            await expect(timesheetSuggestion).toHaveCount(0, { timeout: E2E_TIMEOUT.liveUpdate });
        } finally {
            await Promise.allSettled(contexts.map((context) => context.close()));
            runSql(`
                BEGIN;
                SET LOCAL ihp_roster.allow_hard_delete = 'on';
                DELETE FROM roster_slots WHERE id = '${rosterSlotId}';
                DELETE FROM roster_days WHERE id = '${rosterDayId}';
                DELETE FROM staff_roster_groups WHERE id = '${staffRosterGroupId}';
                DELETE FROM venue_memberships WHERE id = '${membershipId}';
                DELETE FROM staff WHERE id = '${staffId}';
                DELETE FROM users WHERE id = '${userId}';
                UPDATE roster_weeks SET is_live = FALSE WHERE id = 'a1000000-0000-0000-0000-000000000051';
                COMMIT;
            `);
        }
    });
});
