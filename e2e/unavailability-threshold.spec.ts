import { expect, Page, test } from '@playwright/test';
import {
    E2E_TIMEOUT,
    gotoWhenReady,
    loginAs,
    openAdminWithSeededPasskeySession,
    runSql,
} from './test-helpers';

type LiveSubscriptionWindow = Window & { __thresholdSubscriptionKeys?: string[] };

const managerCredentials = {
    email: 'e2e-test@example.com',
    password: 'test-password-123',
};

async function installLiveSubscriptionObserver(page: Page) {
    await page.addInitScript(() => {
        const state = window as LiveSubscriptionWindow;
        state.__thresholdSubscriptionKeys = [];
        document.addEventListener('app:live-update-debug', (event) => {
            const detail = (event as CustomEvent).detail;
            if (detail?.name !== 'subscription_added' || typeof detail.scopeKey !== 'string') return;
            state.__thresholdSubscriptionKeys?.push(detail.scopeKey);
        });
    });
}

async function waitForLeaveSubscription(page: Page) {
    await expect.poll(
        () => page.evaluate(() =>
            (window as LiveSubscriptionWindow).__thresholdSubscriptionKeys?.some((scopeKey) => scopeKey.startsWith('leave-requests:')) ?? false,
        ),
        { timeout: E2E_TIMEOUT.liveUpdate },
    ).toBe(true);
}

async function loginManagerAndOpenLeave(page: Page) {
    await loginAs(page, managerCredentials.email, managerCredentials.password);
    await gotoWhenReady(page, '/LeaveRequests', '#leave-availability-warnings');
    await waitForLeaveSubscription(page);
}

test.describe('Unavailable-staff threshold warnings', () => {
    test('configuration and leave review refresh manager warnings without blocking requests', async ({ browser, page: adminPage }) => {
        const actorContext = await browser.newContext();
        const passiveContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const passivePage = await passiveContext.newPage();
        const alphaNote = 'Alpha leave request';

        try {
            runSql(`
                DROP TABLE IF EXISTS e2e_threshold_leave_backup;
                DROP TABLE IF EXISTS e2e_threshold_config_backup;
                DROP TABLE IF EXISTS e2e_threshold_staff_backup;
                CREATE TABLE e2e_threshold_leave_backup AS
                SELECT id, status, deleted_at, updated_at
                FROM leave_requests
                WHERE venue_id = 'a1000000-0000-0000-0000-000000000001';
                CREATE TABLE e2e_threshold_config_backup AS
                SELECT venue_id, unavailable_staff_warning_threshold, updated_at
                FROM venue_config
                WHERE venue_id = 'a1000000-0000-0000-0000-000000000001';
                CREATE TABLE e2e_threshold_staff_backup AS
                SELECT id, first_name, updated_at
                FROM staff
                WHERE id = 'a1000000-0000-0000-0000-000000000031';
                UPDATE venue_config
                SET unavailable_staff_warning_threshold = NULL, updated_at = NOW()
                WHERE venue_id = 'a1000000-0000-0000-0000-000000000001';
                UPDATE leave_requests
                SET status = 'denied', deleted_at = NULL, updated_at = NOW()
                WHERE venue_id = 'a1000000-0000-0000-0000-000000000001';
                UPDATE leave_requests
                SET status = 'pending', deleted_at = NULL, updated_at = NOW()
                WHERE id = 'a1000000-0000-0000-0000-000000000081';
            `);
            await installLiveSubscriptionObserver(actorPage);
            await installLiveSubscriptionObserver(passivePage);
            await Promise.all([
                loginManagerAndOpenLeave(actorPage),
                loginManagerAndOpenLeave(passivePage),
                openAdminWithSeededPasskeySession(adminPage),
            ]);

            await expect(passivePage.locator('#leave-availability-warnings')).toBeEmpty();
            await adminPage.getByRole('button', { name: 'Venue Settings' }).click();
            await expect(adminPage.locator('#venue-unavailable-staff-warning-threshold')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });

            const thresholdResponsePromise = adminPage.waitForResponse((response) =>
                response.request().method() === 'POST' && response.url().includes('/UpdateVenueConfig'),
            );
            await adminPage.locator('#venue-unavailable-staff-warning-threshold').fill('1');
            await adminPage.locator('#venue-unavailable-staff-warning-threshold').dispatchEvent('change');
            const thresholdResponse = await thresholdResponsePromise;
            expect(thresholdResponse.status(), await thresholdResponse.text()).toBe(200);
            await thresholdResponse.finished();

            await expect(passivePage.locator('#leave-availability-warnings')).toContainText('Unavailable-staff threshold reached', { timeout: E2E_TIMEOUT.liveUpdate });
            await expect(passivePage.locator('#leave-availability-warnings')).toContainText('Alpha Crew');

            await gotoWhenReady(adminPage, '/EditStaff?staffId=a1000000-0000-0000-0000-000000000031&section=profile', '#staff-edit-form');
            const staffEditForm = adminPage.locator('#staff-edit-form:visible');
            await staffEditForm.locator('#firstName').fill('Alpha Live');
            const invalidFieldNames = await staffEditForm.evaluate((form) =>
                Array.from((form as HTMLFormElement).elements)
                    .filter((element): element is HTMLInputElement | HTMLSelectElement =>
                        (element instanceof HTMLInputElement || element instanceof HTMLSelectElement) && !element.checkValidity(),
                    )
                    .map((element) => element.name),
            );
            expect(invalidFieldNames).toEqual([]);
            const staffUpdateResponsePromise = adminPage.waitForResponse((response) =>
                response.request().method() === 'POST' && response.url().includes('/UpdateStaff'),
            );
            await staffEditForm.evaluate(async (formElement) => {
                const form = formElement as HTMLFormElement;
                const body = new URLSearchParams();
                new FormData(form).forEach((value, key) => {
                    if (typeof value === 'string') body.append(key, value);
                });
                await fetch(form.action, {
                    method: 'POST',
                    headers: {
                        'HX-Request': 'true',
                        'Content-Type': 'application/x-www-form-urlencoded',
                    },
                    body: body.toString(),
                });
            });
            const staffUpdateResponse = await staffUpdateResponsePromise;
            expect(staffUpdateResponse.status(), await staffUpdateResponse.text()).toBe(200);
            await staffUpdateResponse.finished();
            await expect(passivePage.locator('#leave-availability-warnings')).toContainText('Alpha Live Crew', { timeout: E2E_TIMEOUT.liveUpdate });

            const actorRow = actorPage.locator('#leave-requests-content article').filter({ hasText: alphaNote });
            const denyResponsePromise = actorPage.waitForResponse((response) =>
                response.request().method() === 'POST' && response.url().includes('/DenyLeaveRequest'),
            );
            await actorRow.getByRole('button', { name: 'Deny' }).click();
            const denyResponse = await denyResponsePromise;
            expect(denyResponse.status(), await denyResponse.text()).toBe(200);
            await denyResponse.finished();

            await expect(passivePage.locator('#leave-availability-warnings')).toBeEmpty({ timeout: E2E_TIMEOUT.liveUpdate });
            await actorPage.locator('#leave-denied-heading button').click();
            await expect(actorPage.locator('#leave-requests-content article').filter({ hasText: alphaNote })).toBeVisible({ timeout: E2E_TIMEOUT.liveUpdate });

            const approveResponsePromise = actorPage.waitForResponse((response) =>
                response.request().method() === 'POST' && response.url().includes('/ApproveLeaveRequest'),
            );
            await actorPage.locator('#leave-requests-content article').filter({ hasText: alphaNote }).getByRole('button', { name: 'Approve' }).click();
            const approveResponse = await approveResponsePromise;
            expect(approveResponse.status(), await approveResponse.text()).toBe(200);
            await approveResponse.finished();

            await expect(passivePage.locator('#leave-availability-warnings')).toContainText('Unavailable-staff threshold reached', { timeout: E2E_TIMEOUT.liveUpdate });
        } finally {
            await actorContext.close();
            await passiveContext.close();
            runSql(`
                UPDATE leave_requests AS request
                SET status = backup.status,
                    deleted_at = backup.deleted_at,
                    updated_at = backup.updated_at
                FROM e2e_threshold_leave_backup AS backup
                WHERE request.id = backup.id;
                UPDATE venue_config AS config
                SET unavailable_staff_warning_threshold = backup.unavailable_staff_warning_threshold,
                    updated_at = backup.updated_at
                FROM e2e_threshold_config_backup AS backup
                WHERE config.venue_id = backup.venue_id;
                UPDATE staff AS staff_member
                SET first_name = backup.first_name,
                    updated_at = backup.updated_at
                FROM e2e_threshold_staff_backup AS backup
                WHERE staff_member.id = backup.id;
                DROP TABLE IF EXISTS e2e_threshold_leave_backup;
                DROP TABLE IF EXISTS e2e_threshold_config_backup;
                DROP TABLE IF EXISTS e2e_threshold_staff_backup;
            `);
        }
    });
});
