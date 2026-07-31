import { expect, Page, test } from '@playwright/test';
import {
    E2E_TIMEOUT,
    gotoWhenReady,
    loginAs,
    openAdminWithSeededPasskeySession,
    runSql,
    setFlatpickrDate,
} from './test-helpers';

type LiveSubscriptionWindow = Window & { __blackoutSubscriptionKeys?: string[] };

async function installSubscriptionObserver(page: Page) {
    await page.addInitScript(() => {
        const state = window as LiveSubscriptionWindow;
        state.__blackoutSubscriptionKeys = [];
        document.addEventListener('app:live-update-debug', (event) => {
            const detail = (event as CustomEvent).detail;
            if (detail?.name !== 'subscription_added' || typeof detail.scopeKey !== 'string') return;
            state.__blackoutSubscriptionKeys?.push(detail.scopeKey);
        });
    });
}

async function waitForSubscription(page: Page, prefix: string) {
    await expect.poll(
        () => page.evaluate((expectedPrefix) =>
            (window as LiveSubscriptionWindow).__blackoutSubscriptionKeys?.some((key) => key.startsWith(expectedPrefix)) ?? false,
        prefix),
        { timeout: E2E_TIMEOUT.liveUpdate },
    ).toBe(true);
}

test.describe('Unavailability submission blackouts', () => {
    test('admins manage periods live while staff submissions remain blocked', async ({ browser, page: adminPage }) => {
        const managerContext = await browser.newContext();
        const workerContext = await browser.newContext();
        const staffManagerContext = await browser.newContext();
        const managerPage = await managerContext.newPage();
        const workerPage = await workerContext.newPage();
        const staffManagerPage = await staffManagerContext.newPage();
        const initialReason = 'E2E annual maintenance closure';
        const updatedReason = 'E2E updated maintenance closure';

        try {
            runSql(`
                DELETE FROM unavailability_blackouts
                WHERE venue_id = 'a1000000-0000-0000-0000-000000000001'
                  AND reason LIKE 'E2E % maintenance closure';
            `);

            await Promise.all([
                installSubscriptionObserver(adminPage),
                installSubscriptionObserver(managerPage),
                installSubscriptionObserver(workerPage),
                installSubscriptionObserver(staffManagerPage),
            ]);

            await openAdminWithSeededPasskeySession(adminPage);
            await gotoWhenReady(adminPage, '/LeaveRequests', '#unavailability-blackouts');
            await loginAs(managerPage, 'e2e-test@example.com', 'test-password-123');
            await gotoWhenReady(managerPage, '/LeaveRequests', '#unavailability-blackouts');
            await loginAs(workerPage, 'e2e-worker@example.com', 'test-password-123');
            await gotoWhenReady(workerPage, '/EditProfile?section=leave', '#self-service-leave-form');
            await loginAs(staffManagerPage, 'e2e-test@example.com', 'test-password-123');
            await gotoWhenReady(staffManagerPage, '/EditStaff?staffId=a1000000-0000-0000-0000-000000000031&section=leave', '#staff-leave-request-form-fragment');
            await staffManagerPage.locator('#staff-leave-request-form-fragment textarea[name="notes"]').fill('Focused manager draft');
            await expect(workerPage.locator('#visible-unavailability-blackouts-fragment')).toBeAttached();

            await Promise.all([
                waitForSubscription(adminPage, 'leave-requests:'),
                waitForSubscription(managerPage, 'leave-requests:'),
                waitForSubscription(workerPage, 'self-service-leave:'),
                waitForSubscription(staffManagerPage, 'staff:'),
            ]);

            await setFlatpickrDate(adminPage, '#blackout-start-date', '2099-10-10');
            await setFlatpickrDate(adminPage, '#blackout-end-date', '2099-10-10');
            await adminPage.locator('#blackout-reason').fill(initialReason);
            const createResponsePromise = adminPage.waitForResponse((response) =>
                response.request().method() === 'POST' && response.url().includes('/CreateUnavailabilityBlackout'),
            );
            await adminPage.getByRole('button', { name: 'Add blackout' }).click();
            const createResponse = await createResponsePromise;
            expect(createResponse.status(), await createResponse.text()).toBe(200);
            await createResponse.finished();

            await expect(managerPage.locator('#unavailability-blackouts')).toContainText(initialReason, { timeout: E2E_TIMEOUT.liveUpdate });
            await expect(managerPage.getByRole('button', { name: 'Add blackout' })).toHaveCount(0);
            await expect(workerPage.locator('#visible-unavailability-blackouts-fragment')).toContainText(initialReason, { timeout: E2E_TIMEOUT.liveUpdate });
            await expect(staffManagerPage.locator('#staff-visible-unavailability-blackouts')).toContainText(initialReason, { timeout: E2E_TIMEOUT.liveUpdate });
            await expect(staffManagerPage.locator('#staff-leave-request-form-fragment textarea[name="notes"]')).toHaveValue('Focused manager draft');

            const workerForm = workerPage.locator('#self-service-leave-form');
            await setFlatpickrDate(workerPage, '#self-service-leave-form input[name="startDate"]', '2099-10-10');
            await setFlatpickrDate(workerPage, '#self-service-leave-form input[name="endDate"]', '2099-10-11');
            const blockedResponsePromise = workerPage.waitForResponse((response) =>
                response.request().method() === 'POST' && response.url().includes('/CreateLeaveRequest'),
            );
            await workerForm.getByRole('button', { name: 'Add unavailable time' }).click();
            const blockedResponse = await blockedResponsePromise;
            expect(blockedResponse.status(), await blockedResponse.text()).toBe(200);
            await blockedResponse.finished();
            await expect(workerPage.locator('#self-service-leave-form-fragment')).toContainText(initialReason);

            const blackoutCard = adminPage.locator('[data-blackout-id]').filter({ hasText: initialReason });
            await blackoutCard.getByText('Edit period').click();
            await blackoutCard.locator('input[name="reason"]').fill(updatedReason);
            const updateResponsePromise = adminPage.waitForResponse((response) =>
                response.request().method() === 'POST' && response.url().includes('/UpdateUnavailabilityBlackout'),
            );
            await blackoutCard.getByRole('button', { name: 'Save blackout' }).click();
            const updateResponse = await updateResponsePromise;
            expect(updateResponse.status(), await updateResponse.text()).toBe(200);
            await updateResponse.finished();
            await expect(managerPage.locator('#unavailability-blackouts')).toContainText(updatedReason, { timeout: E2E_TIMEOUT.liveUpdate });
            await expect(workerPage.locator('#visible-unavailability-blackouts-fragment')).toContainText(updatedReason, { timeout: E2E_TIMEOUT.liveUpdate });

            const updatedCard = adminPage.locator('[data-blackout-id]').filter({ hasText: updatedReason });
            const deleteResponsePromise = adminPage.waitForResponse((response) =>
                response.request().method() === 'DELETE' && response.url().includes('/DeleteUnavailabilityBlackout'),
            );
            await updatedCard.getByRole('button', { name: 'Remove' }).click();
            const deleteResponse = await deleteResponsePromise;
            expect(deleteResponse.status(), await deleteResponse.text()).toBe(200);
            await deleteResponse.finished();
            await expect(managerPage.locator('#unavailability-blackouts')).not.toContainText(updatedReason, { timeout: E2E_TIMEOUT.liveUpdate });
            await expect(workerPage.locator('#visible-unavailability-blackouts-fragment')).not.toContainText(updatedReason, { timeout: E2E_TIMEOUT.liveUpdate });
        } finally {
            await Promise.allSettled([managerContext.close(), workerContext.close(), staffManagerContext.close()]);
            runSql(`
                DELETE FROM unavailability_blackouts
                WHERE venue_id = 'a1000000-0000-0000-0000-000000000001'
                  AND reason LIKE 'E2E % maintenance closure';
            `);
        }
    });
});
