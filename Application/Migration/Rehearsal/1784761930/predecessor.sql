-- Synthetic customer rows for the exact predecessor of billing migration
-- 1784761930. The shared rehearsal harness owns schema reconstruction.
INSERT INTO users (id, email, password_hash)
VALUES (
    'a0000000-0000-0000-0000-000000000001',
    'billing-rehearsal@example.invalid',
    'synthetic-not-a-real-password-hash'
);

INSERT INTO venues (id, name)
VALUES ('a1000000-0000-0000-0000-000000000001', 'Preserved Venue');

INSERT INTO venue_billing_customers (venue_id, stripe_customer_id)
VALUES ('a1000000-0000-0000-0000-000000000001', 'cus_preserved');

INSERT INTO venue_subscriptions (
    venue_id,
    stripe_subscription_id,
    stripe_price_id,
    status
) VALUES (
    'a1000000-0000-0000-0000-000000000001',
    'sub_preserved',
    'price_preserved',
    'active'
);

INSERT INTO billing_events (
    stripe_event_id,
    event_type,
    status,
    processed_at,
    venue_id,
    stripe_customer_id,
    stripe_subscription_id
) VALUES (
    'evt_preserved',
    'customer.subscription.updated',
    'processed',
    NOW(),
    'a1000000-0000-0000-0000-000000000001',
    'cus_preserved',
    'sub_preserved'
);
