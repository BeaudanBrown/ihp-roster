import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { expect, test } from '@playwright/test';

declare const process: { env: Record<string, string | undefined> };
import {
    E2E_TIMEOUT,
    clearCurrentSessionPasskeyVerification,
    gotoWhenReady,
    loginAsPrivilegedUserWithSeededPasskeySession,
    markCurrentSessionPasskeyVerified,
} from './test-helpers';

const apiVersion = '2026-06-24.dahlia';
const venueId = 'a1000000-0000-0000-0000-000000000001';
const customerId = 'cus_e2e-123';
const firstSessionId = 'cs_e2e-123';
const retrySessionId = 'cs_e2e-retry-456';
const subscriptionId = 'sub_e2e-123';
const webhookSecret = 'whsec_e2e_strict_boundary';
let providerEventSequence = 0;

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

function checkoutEvent(eventId: string, type: string, checkoutSessionId: string, checkoutSubscriptionId: string) {
    return {
        id: eventId,
        object: 'event',
        api_version: apiVersion,
        created: nextProviderCreatedAt(),
        livemode: false,
        type,
        data: {
            object: {
                id: checkoutSessionId,
                object: 'checkout.session',
                client_reference_id: venueId,
                customer: customerId,
                livemode: false,
                metadata: { venue_id: venueId },
                status: 'complete',
                subscription: checkoutSubscriptionId,
            },
        },
    };
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
    test('keeps owner actions stepped-up, correlates Checkout, refreshes lifecycle state, and separates founder diagnostics', async ({ page, request }) => {
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
        await expect(page).toHaveURL(/(EditProfile|RosterWeeks|ShowRosterWeek)/, { timeout: E2E_TIMEOUT.navigation });
        await gotoWhenReady(page, '/Billing', '[data-billing-owner-view="true"]');
        await expect(page.getByText('No subscription', { exact: true })).toBeVisible();
        await expect(page.getByRole('button', { name: 'Start Subscription' })).toBeEnabled();
        await expect(page.locator('header a[href="/Billing"]')).toBeVisible();
        await clearCurrentSessionPasskeyVerification(page);

        await page.getByRole('button', { name: 'Start Subscription' }).click();
        await expect(page).toHaveURL(/PasskeyStepUp/, { timeout: E2E_TIMEOUT.navigation });
        const statusBeforePaymentAction = await request.get(`${mockBaseUrl}/__status`);
        expect((await statusBeforePaymentAction.json()).consumed).toEqual([]);

        await gotoWhenReady(page, '/Billing', '[data-billing-owner-view="true"]');
        await markCurrentSessionPasskeyVerified(page);
        const checkoutResponse = await page.request.post('/CreateBillingCheckoutSession', { maxRedirects: 0 });
        expect(checkoutResponse.status()).toBe(302);
        expect(checkoutResponse.headers().location).toBe('https://checkout.stripe.com/c/pay/cs_test_e2e-sanitized');

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

        await gotoWhenReady(
            page,
            `/BillingSuccess?attempt_id=${encodeURIComponent(failedAttemptId ?? '')}&session_id=${firstSessionId}`,
            '[data-billing-owner-view="true"]',
        );
        await expect(page.getByText('Finalising subscription', { exact: true })).toBeVisible();
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

        await deliverSignedWebhook(page, checkoutEvent(
            'evt_e2e-checkout_async_failed',
            'checkout.session.async_payment_failed',
            firstSessionId,
            'sub_e2e-failed-123',
        ));
        await expect(page.getByText('Subscription needs attention', { exact: true })).toBeVisible({ timeout: E2E_TIMEOUT.liveUpdate });

        await gotoWhenReady(page, '/Billing', '[data-billing-owner-view="true"]');
        await expect(page.getByText('No subscription', { exact: true })).toBeVisible();
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

        await gotoWhenReady(
            page,
            `/BillingSuccess?attempt_id=${encodeURIComponent(confirmedAttemptId ?? '')}&session_id=${retrySessionId}`,
            '[data-billing-owner-view="true"]',
        );
        await expect(page.getByText('Finalising subscription', { exact: true })).toBeVisible();
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
        ] });

        await deliverSignedWebhook(page, checkoutEvent(
            'evt_e2e-checkout_completed',
            'checkout.session.completed',
            retrySessionId,
            subscriptionId,
        ));
        await deliverSignedWebhook(page, subscriptionEvent('evt_e2e-subscription_created', 'customer.subscription.created', 'active'));
        const confirmedFragmentRefresh = page.waitForResponse(
            (response) => response.url().includes('/ShowbillingStatusLiveFragment'),
            { timeout: E2E_TIMEOUT.liveUpdate },
        );
        await deliverSignedWebhook(page, subscriptionEvent('evt_e2e-subscription_active_refresh', 'customer.subscription.updated', 'active'));
        await confirmedFragmentRefresh;
        await expect(page.getByText('Subscription confirmed', { exact: true })).toBeVisible({ timeout: E2E_TIMEOUT.liveUpdate });
        await expect(page.getByText('Active', { exact: true })).toBeVisible();

        const ownerHtml = await page.locator('[data-billing-owner-view="true"]').innerHTML();
        for (const forbidden of [customerId, firstSessionId, retrySessionId, subscriptionId, 'evt_e2e', 'processing failed', 'Stripe synchronization']) {
            expect(ownerHtml).not.toContain(forbidden);
        }

        await gotoWhenReady(page, '/Billing', '[data-billing-owner-view="true"]');
        await expect(page.getByRole('button', { name: 'Manage Billing' })).toBeVisible();
        const portalResponse = await page.request.post('/CreateBillingPortalSession', { maxRedirects: 0 });
        expect(portalResponse.status()).toBe(302);
        expect(portalResponse.headers().location).toBe('https://billing.stripe.com/p/session/bps_test_sanitized');

        await gotoWhenReady(page, '/Billing', '[data-billing-owner-view="true"]');
        await deliverSignedWebhook(page, invoicePaymentFailedEvent('evt_e2e-invoice_payment_failed'));
        await deliverSignedWebhook(page, subscriptionEvent('evt_e2e-subscription_past_due', 'customer.subscription.updated', 'past_due'));
        await expect(page.getByText('Payment needs attention', { exact: true })).toBeVisible({ timeout: E2E_TIMEOUT.liveUpdate });
        await deliverSignedWebhook(page, subscriptionEvent('evt_e2e-subscription_cancel_pending', 'customer.subscription.updated', 'active', true));
        await expect(page.getByText('Cancellation scheduled', { exact: true }).first()).toBeVisible({ timeout: E2E_TIMEOUT.liveUpdate });
        await deliverSignedWebhook(page, subscriptionEvent('evt_e2e-subscription_deleted', 'customer.subscription.deleted', 'canceled'));
        await expect(page.getByText('Canceled', { exact: true })).toBeVisible({ timeout: E2E_TIMEOUT.liveUpdate });
        await deliverSignedWebhook(page, subscriptionEvent('evt_e2e-subscription_expired', 'customer.subscription.updated', 'incomplete_expired'));
        await expect(page.getByText('Setup expired', { exact: true })).toBeVisible({ timeout: E2E_TIMEOUT.liveUpdate });

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
                'POST /v1/billing_portal/sessions',
            ],
            failures: [],
        });

        await page.context().clearCookies();
        await loginAsPrivilegedUserWithSeededPasskeySession(page, 'e2e-super-admin@example.com');
        await gotoWhenReady(page, '/Billing', '[data-billing-founder-diagnostics="true"]');
        await expect(page.getByText('Billing diagnostics', { exact: true })).toBeVisible();
        await expect(page.getByRole('button', { name: /Start Subscription|Restart Subscription|Manage Billing|Resolve Payment/ })).toHaveCount(0);
        await expect(page.locator('header a[href="/Billing"]')).toHaveCount(0);
    });
});
