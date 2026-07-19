import { test, expect, type Page } from '@playwright/test';
import { dialogMountDomAttr, dialogOverlayMountDomId, toastOverlayMountDomId } from '../frontend/ts/generated/contracts';
import { openRoster } from './test-helpers';

async function loginAndOpenRoster(page: Page) {
    await openRoster(page, { email: 'e2e-test@example.com' });
    await expect(page.locator('.roster-staff-panel')).toBeVisible();
}

test.describe('Roster Staff Modal', () => {
    test('opens the dedicated trial invitation dialog without opening staff edit', async ({ page }) => {
        await loginAndOpenRoster(page);

        const initialUrl = page.url();
        const modalMount = page.locator(`#${dialogOverlayMountDomId}`);
        const trialEntry = page.locator('.roster-staff-panel-entry[data-roster-staff-role="TRIAL"]:visible').first();
        const inviteButton = trialEntry.getByRole('button', { name: /^Invite / });

        await expect(inviteButton).toBeVisible();
        await inviteButton.click();

        await expect(page).toHaveURL(initialUrl);
        await expect(modalMount.locator(`[${dialogMountDomAttr}]`)).toBeVisible();
        await expect(modalMount).toContainText('Invite trial staff');
        await expect(modalMount).not.toContainText('Edit Staff Member');
        await expect(modalMount.locator('#trial-staff-invite-form')).toBeVisible();
    });

    test('edits staff inline without navigating away from the roster', async ({ page }) => {
        await loginAndOpenRoster(page);

        const initialUrl = page.url();
        const modalMount = page.locator(`#${dialogOverlayMountDomId}`);
        const staffEntry = page.locator('.roster-staff-panel-entry:visible').first();
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

    test('admin profile save refreshes roster staff names and exposes the venue role control', async ({ page }) => {
        await openRoster(page, { email: 'e2e-admin@example.com' });

        const modalMount = page.locator(`#${dialogOverlayMountDomId}`);
        const staffPanel = page.locator('.roster-staff-panel');
        const rosterGrid = page.locator('.roster-grid-frame');
        const alphaEntry = staffPanel.locator('.roster-staff-panel-entry').filter({ has: page.getByRole('rowheader', { name: 'Alpha', exact: true }) });
        await expect(alphaEntry).toBeVisible();
        await expect(rosterGrid).toContainText('Alpha');
        await alphaEntry.click();

        await modalMount.getByRole('button', { name: 'Profile Details' }).click();
        const staffEditForm = modalMount.locator('#staff-edit-form:visible');
        const venueRole = staffEditForm.locator('#venueRole');
        await expect(venueRole).toBeVisible();
        await expect(venueRole.getByRole('option', { name: 'Manager' })).toHaveCount(1);

        await staffEditForm.locator('#firstName').fill('Alphonso');
        const rosterSwapsPromise = page.evaluate(() => new Promise<void>((resolve) => {
            const pendingTargets = new Set(['roster-content', 'roster-staff-panel-fragment']);
            document.addEventListener('app:live-update-performance', (event) => {
                const detail = (event as CustomEvent<Record<string, unknown>>).detail;
                if (detail?.name !== 'live_updates.swap_fragment' || detail?.outcome !== 'swapped' || typeof detail?.targetId !== 'string') return;
                pendingTargets.delete(detail.targetId);
                if (pendingTargets.size === 0) resolve();
            });
        }));
        const updateResponsePromise = page.waitForResponse((response) => response.request().method() === 'POST' && response.url().includes('/UpdateStaff'));
        const rosterRefreshPromise = page.waitForResponse((response) => response.request().method() === 'GET' && response.url().includes('/ShowRosterWeekContentFragment'));
        const staffListRefreshPromise = page.waitForResponse((response) => response.request().method() === 'GET' && response.url().includes('/ShowRosterWeekStaffPanelFragment'));
        await staffEditForm.getByRole('button', { name: 'Save profile details' }).click();
        const updateResponse = await updateResponsePromise;
        expect(updateResponse.headers()['hx-trigger']).toContain('roster-content');
        const rosterRefreshResponse = await rosterRefreshPromise;
        const staffListRefreshResponse = await staffListRefreshPromise;
        await Promise.all([rosterRefreshResponse.finished(), staffListRefreshResponse.finished()]);
        expect(await rosterRefreshResponse.text()).toContain('Alphonso');
        expect(await staffListRefreshResponse.text()).toContain('Alphonso');
        await rosterSwapsPromise;

        await expect(page.locator(`#${toastOverlayMountDomId}`)).toContainText('Staff member updated');
        await expect(staffPanel).toContainText('Alphonso');
        await expect(staffPanel).not.toContainText('Alpha');
        await expect(rosterGrid).toContainText('Alphonso');
        await expect(rosterGrid).not.toContainText('Alpha');
    });
});
