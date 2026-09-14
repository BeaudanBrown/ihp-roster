import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { expect, test } from '@playwright/test';

declare const process: { env: Record<string, string | undefined> };
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady } from './support/runtime';
import { loginAsPrivilegedUserWithSeededPasskeySession, markCurrentSessionPasskeyVerified } from './support/passkeys';
import { querySql, runSql } from './support/database';

const apiVersion = '2026-06-24.dahlia';
const venueId = 'a1000000-0000-0000-0000-000000000001';
const customerId = 'cus_e2e-123';
const firstSessionId = 'cs_e2e-123';
const retrySessionId = 'cs_e2e-retry-456';
const subscriptionId = 'sub_e2e-123';
const webhookSecret = 'whsec_e2e_strict_boundary';
let providerEventSequence = 0;

function deferBillingReconciliationJobs() {
    runSql(`
        CREATE OR REPLACE FUNCTION e2e_defer_billing_reconciliation_jobs()
        RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
            NEW.run_at := NOW() + INTERVAL '1 hour';
            RETURN NEW;
        END;
        $$;
        DROP TRIGGER IF EXISTS e2e_defer_billing_reconciliation_jobs ON app_jobs;
        CREATE TRIGGER e2e_defer_billing_reconciliation_jobs
            BEFORE INSERT ON app_jobs
            FOR EACH ROW
            WHEN (NEW.job_kind = 'billing_reconciliation')
            EXECUTE FUNCTION e2e_defer_billing_reconciliation_jobs();
    `);
}

function releaseBillingReconciliationJobs() {
    runSql(`
        DROP TRIGGER IF EXISTS e2e_defer_billing_reconciliation_jobs ON app_jobs;
        UPDATE app_jobs
        SET run_at = NOW(), status = 'job_status_retry', updated_at = NOW()
        WHERE job_kind = 'billing_reconciliation'
          AND status = 'job_status_not_started';
        DROP FUNCTION IF EXISTS e2e_defer_billing_reconciliation_jobs();
    `);
}

function cleanupDeferredBillingReconciliationJobs() {
    runSql(`
        DROP TRIGGER IF EXISTS e2e_defer_billing_reconciliation_jobs ON app_jobs;
        DROP FUNCTION IF EXISTS e2e_defer_billing_reconciliation_jobs();
        UPDATE app_jobs
        SET run_at = NOW(), status = 'job_status_retry', updated_at = NOW()
        WHERE job_kind = 'billing_reconciliation'
          AND status = 'job_status_not_started'
          AND run_at > NOW();
    `);
}

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

function nextProviderCreatedAt() {
    providerEventSequence += 1;
    return Math.floor(Date.now() / 1000) + providerEventSequence;
}

type ReviewedWebhookFixture = {
    id: string;
    object: string;
    api_version: string;
    created: number;
    livemode: boolean;
    type: string;
    data: { object: unknown };
};

function reviewedWebhookFixture(filename: string): ReviewedWebhookFixture {
    return JSON.parse(readFileSync(`Test/Fixtures/stripe/${apiVersion}/${filename}`, 'utf8')) as ReviewedWebhookFixture;
}

function subscriptionEvent(eventId: string, type: string, status: string, cancelAtPeriodEnd = false) {
    const fixtureName = type === 'customer.subscription.created'
        ? 'webhook-subscription-created.json'
        : type === 'customer.subscription.deleted'
            ? 'webhook-subscription-deleted.json'
            : 'webhook-subscription-updated.json';
    const event = reviewedWebhookFixture(fixtureName);
    const created = nextProviderCreatedAt();
    const subscription = event.data.object as {
        id: string;
        cancel_at_period_end: boolean;
        customer: string;
        status: string;
        metadata: Record<string, string>;
        items: { data: Array<{
            id: string;
            current_period_start: number;
            current_period_end: number;
            price: { id: string };
            subscription: string;
        }> };
    };
    event.id = eventId;
    event.created = created;
    event.type = type;
    subscription.id = subscriptionId;
    subscription.cancel_at_period_end = cancelAtPeriodEnd;
    subscription.customer = customerId;
    subscription.status = status;
    subscription.metadata = { venue_id: venueId };
    subscription.items.data[0].id = 'si_e2e-123';
    subscription.items.data[0].current_period_start = created - 60;
    subscription.items.data[0].current_period_end = created + 2_592_000;
    subscription.items.data[0].price.id = 'price_valid';
    subscription.items.data[0].subscription = subscriptionId;
    return event;
}

function invoicePaymentFailedEvent(eventId: string) {
    const event = reviewedWebhookFixture('webhook-invoice-payment-failed.json');
    const created = nextProviderCreatedAt();
    const invoice = event.data.object as {
        id: string;
        customer: string;
        parent: { subscription_details: { subscription: string; metadata: Record<string, string> } };
        period_start: number;
        period_end: number;
    };
    event.id = eventId;
    event.created = created;
    invoice.id = 'in_e2e-failed-123';
    invoice.customer = customerId;
    invoice.parent.subscription_details.subscription = subscriptionId;
    invoice.parent.subscription_details.metadata = { venue_id: venueId };
    invoice.period_start = created - 60;
    invoice.period_end = created + 2_592_000;
    return event;
}

async function followHostedBillingRedirect(page: import('@playwright/test').Page, buttonName: string, actionPath: string, hostedUrl: string) {
    // Never browse Stripe: only the local mock's fixed hosted destination is served.
    await page.route(hostedUrl, (route) => route.fulfill({ contentType: 'text/plain', body: 'Local hosted billing destination' }));
    await page.route(`**${actionPath}`, async (route) => {
        expect(route.request().headers()['hx-request']).toBe('true');
        const response = await route.fetch({ maxRedirects: 0 });
        expect(response.status()).toBe(200);
        expect(response.headers()['hx-redirect']).toBe(hostedUrl);
        expect(response.headers().location).toBeUndefined();
        expect(await response.text()).toBe('');
        // Forward the real application response unchanged, after capturing its
        // body before navigation can discard the browser's response buffer.
        await route.fulfill({ response });
    }, { times: 1 });
    await page.getByRole('button', { name: buttonName, exact: true }).click();
    await expect(page).toHaveURL(hostedUrl, { timeout: E2E_TIMEOUT.navigation });
    await expect(page.getByText('Local hosted billing destination', { exact: true })).toBeVisible();
}

async function deliverSignedWebhook(page: import('@playwright/test').Page, payload: object) {
    const body = JSON.stringify(payload);
    execFileSync('python3', ['scripts/check-stripe-openapi-contract', '--validate-webhook-stdin'], {
        input: body,
        stdio: ['pipe', 'ignore', 'inherit'],
    });
    const timestamp = Math.floor(Date.now() / 1000);
    const key = await crypto.subtle.importKey(
        'raw',
        new TextEncoder().encode(webhookSecret),
        { name: 'HMAC', hash: 'SHA-256' },
        false,
        ['sign'],
    );
    const digest = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${timestamp}.${body}`));
    const signature = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
    const response = await page.request.post('/StripeWebhook', {
        data: body,
        headers: {
            'Content-Type': 'application/json',
            'Stripe-Signature': `t=${timestamp},v1=${signature}`,
        },
    });
    expect(response.status()).toBe(200);
}

test.describe('Billing through the strict local Stripe boundary', () => {
    test.afterEach(() => cleanupDeferredBillingReconciliationJobs());

    test('shows a blocking loading dialog before a Stripe navigation request completes', async ({ page }) => {
        await page.addInitScript(() => {
            const captureLoadingDialog = () => {
                const dialog = document.querySelector('[role="dialog"][aria-label="Opening Stripe"]');
                if (!(dialog instanceof HTMLElement)) return;
                sessionStorage.setItem('e2e-billing-loading-dialog', JSON.stringify({
                    visible: !dialog.hidden,
                    text: dialog.textContent ?? '',
                    spinnerCount: dialog.querySelectorAll('.spinner-border').length,
                    buttonCount: dialog.querySelectorAll('button').length,
                }));
            };
            new MutationObserver(captureLoadingDialog).observe(document, { childList: true, subtree: true });
            document.addEventListener('DOMContentLoaded', captureLoadingDialog, { once: true });
        });
        await gotoWhenReady(page, '/NewSession', '#email');
        await page.fill('#email', 'e2e-billing-owner@example.com');
        await page.fill('#password', 'test-password-123');
        await page.click('button[type="submit"]');
        await expect(page).toHaveURL(/(EditProfile|RosterWeeks|ShowRosterWindow)/, { timeout: E2E_TIMEOUT.navigation });
        await markCurrentSessionPasskeyVerified(page);
        await gotoWhenReady(page, '/Billing', '[data-billing-owner-view="true"]');

        const startSubscription = page.getByRole('button', { name: 'Subscribe' });
        const stripeLoadingDialog = page.getByRole('dialog', { name: 'Opening Stripe' });
        await expect(stripeLoadingDialog).toHaveCount(0);

        let releaseRequest!: () => void;
        let markRequestObserved!: () => void;
        const requestObserved = new Promise<void>((resolve) => { markRequestObserved = resolve; });
        const heldRequest = new Promise<void>((resolve) => { releaseRequest = resolve; });
        await page.route('**/CreateBillingCheckoutSession', async (route) => {
            markRequestObserved();
            await heldRequest;
            await route.fulfill({ status: 303, headers: { Location: '/Billing' } });
        });

        const clickPromise = startSubscription.click();
        await requestObserved;
        releaseRequest();
        await clickPromise;
        await expect(page).toHaveURL(/Billing/, { timeout: E2E_TIMEOUT.navigation });
        const loadingDialog = JSON.parse(await page.evaluate(() => sessionStorage.getItem('e2e-billing-loading-dialog') ?? 'null')) as {
            visible: boolean;
            text: string;
            spinnerCount: number;
            buttonCount: number;
        } | null;
        expect(loadingDialog).not.toBeNull();
        expect(loadingDialog?.visible).toBe(true);
        expect(loadingDialog?.text).toContain('Opening Stripe');
        expect(loadingDialog?.text).toContain("Please wait while Bepis opens Stripe's secure billing page.");
        expect(loadingDialog?.spinnerCount).toBe(1);
        expect(loadingDialog?.buttonCount).toBe(0);
        await expect(stripeLoadingDialog).toHaveCount(0);
    });

    test('correlates Checkout, refreshes lifecycle state, and separates founder diagnostics', async ({ browser, page, request }) => {
        test.setTimeout(E2E_TIMEOUT.slowTest * 2);
        const mockBaseUrl = process.env.STRIPE_MOCK_BASE_URL;
        if (!mockBaseUrl) throw new Error('STRIPE_MOCK_BASE_URL is required for billing E2E');
        await page.addInitScript(() => {
            const state = window as Window & { __billingLiveSubscriptionReady?: boolean };
            state.__billingLiveSubscriptionReady = false;
            document.addEventListener('app:live-update-debug', (event) => {
                const detail = (event as CustomEvent).detail;
                if (detail?.name === 'subscription_added' && String(detail.scopeKey).startsWith('billing')) {
                    state.__billingLiveSubscriptionReady = true;
                }
            });
        });

        await gotoWhenReady(page, '/NewSession', '#email');
        await page.fill('#email', 'e2e-billing-owner@example.com');
        await page.fill('#password', 'test-password-123');
        await page.click('button[type="submit"]');
        await expect(page).toHaveURL(/(EditProfile|RosterWeeks|ShowRosterWindow)/, { timeout: E2E_TIMEOUT.navigation });
        await gotoWhenReady(page, '/Billing', '[data-billing-owner-view="true"]');
        const ownerBillingView = page.locator('[data-billing-owner-view="true"]');
        await expect(ownerBillingView.getByText('Subscription Inactive :-(', { exact: true })).toBeVisible();
        await expect(ownerBillingView.locator('[data-billing-subscription-status="inactive"]')).toBeVisible();
        await expect(ownerBillingView.locator('.badge')).toHaveCount(0);
        await expect(page.locator('.app-page-description')).toHaveText('If you like Bepis, please support its development by subscribing.');
        await expect(ownerBillingView.getByText('If you like Bepis, please support its development by subscribing.', { exact: true })).toHaveCount(0);
        await expect(page.getByText('$100/month', { exact: true })).toBeVisible();
        await expect(page.getByRole('button', { name: 'Subscribe' })).toBeEnabled();
        const desktopBillingLink = page.locator('header a[href="/Billing"]');
        await expect(desktopBillingLink).toBeVisible();
        await expect(desktopBillingLink).toHaveClass(/app-header-nav-item-warning/);
        await expect(desktopBillingLink).toHaveAttribute('aria-label', 'Billing — subscription inactive');

        await followHostedBillingRedirect(page, 'Subscribe', '/CreateBillingCheckoutSession', 'https://checkout.stripe.com/c/pay/cs_test_e2e-sanitized');

        await expect.poll(async () => {
            const response = await request.get(`${mockBaseUrl}/__status`);
            return response.json();
        }, { timeout: E2E_TIMEOUT.assertion }).toMatchObject({
            consumed: ['GET /v1/prices#1', 'POST /v1/customers', 'POST /v1/checkout/sessions#1'],
            failures: [],
        });
        let mockStatusResponse = await request.get(`${mockBaseUrl}/__status`);
        let mockStatus = await mockStatusResponse.json() as { attemptIds?: string[] };
        const failedAttemptId = mockStatus.attemptIds?.[0];
        expect(failedAttemptId).toBeTruthy();

        deferBillingReconciliationJobs();
        const firstPendingRender = page.waitForResponse((response) =>
            response.url().includes('/Billing?checkout=success') && response.request().resourceType() === 'document',
        );
        await gotoWhenReady(
            page,
            `/BillingSuccess?attempt_id=${encodeURIComponent(failedAttemptId ?? '')}&session_id=${firstSessionId}`,
            '[data-billing-owner-view="true"]',
        );
        expect(await (await firstPendingRender).text()).toContain('Finalising subscription');
        await expect(page.getByText('Finalising subscription', { exact: true })).toBeVisible();
        releaseBillingReconciliationJobs();
        await expect.poll(
            () => page.evaluate(() => (window as Window & { __billingLiveSubscriptionReady?: boolean }).__billingLiveSubscriptionReady ?? false),
            { timeout: E2E_TIMEOUT.liveUpdate },
        ).toBe(true);
        await expect.poll(async () => {
            const response = await request.get(`${mockBaseUrl}/__status`);
            return response.json();
        }, { timeout: E2E_TIMEOUT.liveUpdate }).toMatchObject({ consumed: [
            'GET /v1/prices#1',
            'POST /v1/customers',
            'POST /v1/checkout/sessions#1',
            'GET /v1/checkout/sessions/cs_e2e-123',
        ] });

        await expect(page.getByText('Subscription needs attention', { exact: true })).toBeVisible({ timeout: E2E_TIMEOUT.liveUpdate });

        await gotoWhenReady(page, '/Billing', '[data-billing-owner-view="true"]');
        await expect(ownerBillingView.getByText('Subscription Inactive :-(', { exact: true })).toBeVisible();
        const retryCheckoutResponse = await page.request.post('/CreateBillingCheckoutSession', { maxRedirects: 0 });
        expect(retryCheckoutResponse.status()).toBe(302);
        expect(retryCheckoutResponse.headers().location).toBe('https://checkout.stripe.com/c/pay/cs_test_e2e-retry-sanitized');
        await expect.poll(async () => {
            const response = await request.get(`${mockBaseUrl}/__status`);
            return response.json();
        }, { timeout: E2E_TIMEOUT.assertion }).toMatchObject({ consumed: [
            'GET /v1/prices#1',
            'POST /v1/customers',
            'POST /v1/checkout/sessions#1',
            'GET /v1/checkout/sessions/cs_e2e-123',
            'GET /v1/prices#2',
            'POST /v1/checkout/sessions#2',
        ] });
        mockStatusResponse = await request.get(`${mockBaseUrl}/__status`);
        mockStatus = await mockStatusResponse.json() as { attemptIds?: string[] };
        const confirmedAttemptId = mockStatus.attemptIds?.[1];
        expect(confirmedAttemptId).toBeTruthy();

        deferBillingReconciliationJobs();
        const secondPendingRender = page.waitForResponse((response) =>
            response.url().includes('/Billing?checkout=success') && response.request().resourceType() === 'document',
        );
        await gotoWhenReady(
            page,
            `/BillingSuccess?attempt_id=${encodeURIComponent(confirmedAttemptId ?? '')}&session_id=${retrySessionId}`,
            '[data-billing-owner-view="true"]',
        );
        expect(await (await secondPendingRender).text()).toContain('Finalising subscription');
        await expect(page.getByText('Finalising subscription', { exact: true })).toBeVisible();
        await expect.poll(
            () => page.evaluate(() => (window as Window & { __billingLiveSubscriptionReady?: boolean }).__billingLiveSubscriptionReady ?? false),
            { timeout: E2E_TIMEOUT.liveUpdate },
        ).toBe(true);
        const preDisconnectEventSequence = Number(querySql(`
            SELECT COALESCE(MAX(sequence_number), 0)
            FROM live_invalidation_events;
        `).trim());
        disconnectDurableInvalidationListeners();
        releaseBillingReconciliationJobs();
        await expect.poll(async () => {
            const response = await request.get(`${mockBaseUrl}/__status`);
            return response.json();
        }, { timeout: E2E_TIMEOUT.liveUpdate }).toMatchObject({ consumed: [
            'GET /v1/prices#1',
            'POST /v1/customers',
            'POST /v1/checkout/sessions#1',
            'GET /v1/checkout/sessions/cs_e2e-123',
            'GET /v1/prices#2',
            'POST /v1/checkout/sessions#2',
            'GET /v1/checkout/sessions/cs_e2e-retry-456',
            'GET /v1/subscriptions/sub_e2e-123',
        ] });

        await expect(page.getByText('Subscription confirmed', { exact: true })).toBeVisible({ timeout: E2E_TIMEOUT.liveUpdate });
        await expect(ownerBillingView.locator('[data-billing-subscription-status="active"]')).toContainText('Subscription Active :-)');
        await expect(page.getByRole('button', { name: 'Check again' })).toHaveCount(0);
        await expect.poll(() => querySql(`
            SELECT EXISTS (
                SELECT 1
                FROM pg_stat_activity listener
                JOIN live_invalidation_events event
                  ON event.source = 'billing.reconciliation.complete'
                WHERE listener.application_name = 'bepis-live-invalidation-listener'
                  AND listener.datname = current_database()
                  AND event.sequence_number > ${preDisconnectEventSequence}
                  AND listener.backend_start > event.created_at
                ORDER BY event.sequence_number DESC
                LIMIT 1
            );
        `).trim(), { timeout: E2E_TIMEOUT.liveUpdate }).toBe('t');

        const duplicateProviderEvent = subscriptionEvent('evt_e2e-subscription_duplicate', 'customer.subscription.updated', 'active');
        await deliverSignedWebhook(page, duplicateProviderEvent);
        await deliverSignedWebhook(page, duplicateProviderEvent);
        await expect(page.getByText('Subscription confirmed', { exact: true })).toBeVisible({ timeout: E2E_TIMEOUT.liveUpdate });

        const ownerHtml = await page.locator('[data-billing-owner-view="true"]').innerHTML();
        for (const forbidden of [customerId, firstSessionId, retrySessionId, subscriptionId, 'evt_e2e', 'processing failed', 'Stripe synchronization']) {
            expect(ownerHtml).not.toContain(forbidden);
        }

        await gotoWhenReady(page, '/Billing', '[data-billing-owner-view="true"]');
        await expect(page.locator('.app-page-description')).toHaveText('Thank you for supporting the development of Bepis.');
        await expect(ownerBillingView.locator('[data-billing-subscription-status="active"]')).toContainText('Subscription Active :-)');
        await expect(page.getByText('$100/month', { exact: true })).toBeVisible();
        await expect(page.getByRole('button', { name: 'Manage Billing' })).toBeVisible();
        await followHostedBillingRedirect(page, 'Manage Billing', '/CreateBillingPortalSession', 'https://billing.stripe.com/p/session/bps_test_sanitized');

        await gotoWhenReady(page, '/Billing', '[data-billing-owner-view="true"]');
        await deliverSignedWebhook(page, invoicePaymentFailedEvent('evt_e2e-invoice_payment_failed'));
        await deliverSignedWebhook(page, subscriptionEvent('evt_e2e-subscription_past_due', 'customer.subscription.updated', 'past_due'));
        await expect(ownerBillingView.getByText('Subscription Inactive :-(', { exact: true })).toBeVisible({ timeout: E2E_TIMEOUT.liveUpdate });
        await deliverSignedWebhook(page, subscriptionEvent('evt_e2e-subscription_cancel_pending', 'customer.subscription.updated', 'active', true));
        const scheduledCancellationStatus = ownerBillingView.locator('[data-billing-subscription-status="cancellation-scheduled"]');
        await expect(scheduledCancellationStatus.getByText('Cancellation scheduled.', { exact: true })).toBeVisible({ timeout: E2E_TIMEOUT.liveUpdate });
        await expect(scheduledCancellationStatus.getByText(/This subscription remains active until .* and will not renew\./)).toBeVisible({ timeout: E2E_TIMEOUT.liveUpdate });
        await deliverSignedWebhook(page, subscriptionEvent('evt_e2e-subscription_deleted', 'customer.subscription.deleted', 'canceled'));
        await expect(ownerBillingView.getByText('Subscription Inactive :-(', { exact: true })).toBeVisible({ timeout: E2E_TIMEOUT.liveUpdate });
        await deliverSignedWebhook(page, subscriptionEvent('evt_e2e-subscription_expired', 'customer.subscription.updated', 'incomplete_expired'));
        await expect(ownerBillingView.getByText('Subscription Inactive :-(', { exact: true })).toBeVisible({ timeout: E2E_TIMEOUT.liveUpdate });

        const finalMockStatusResponse = await request.get(`${mockBaseUrl}/__status`);
        expect(await finalMockStatusResponse.json()).toMatchObject({
            consumed: [
                'GET /v1/prices#1',
                'POST /v1/customers',
                'POST /v1/checkout/sessions#1',
                'GET /v1/checkout/sessions/cs_e2e-123',
                'GET /v1/prices#2',
                'POST /v1/checkout/sessions#2',
                'GET /v1/checkout/sessions/cs_e2e-retry-456',
                'GET /v1/subscriptions/sub_e2e-123',
                'POST /v1/billing_portal/sessions',
            ],
            failures: [],
        });

        const founderContext = await browser.newContext({ baseURL: new URL(page.url()).origin });
        const founderPage = await founderContext.newPage();
        try {
            await loginAsPrivilegedUserWithSeededPasskeySession(founderPage, 'e2e-super-admin@example.com');
            await gotoWhenReady(founderPage, '/Billing', '[data-billing-founder-diagnostics="true"]');
            await expect(founderPage.getByText('Billing diagnostics', { exact: true })).toBeVisible();
            await expect(founderPage.getByRole('button', { name: /Subscribe|Manage subscription|Manage Billing/ })).toHaveCount(0);
            await expect(founderPage.locator('header a[href="/Billing"]')).toHaveCount(0);
        } finally {
            await founderContext.close();
        }
    });
});
