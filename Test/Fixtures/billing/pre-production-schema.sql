-- Representative schema immediately before Application/Migration/1784761930.sql.
-- It intentionally contains customer data so the upgrade test proves the billing
-- hardening migration is additive rather than merely checking migration text.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE users (
    id UUID PRIMARY KEY
);

CREATE TABLE venues (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL
);

CREATE TABLE venue_billing_customers (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL UNIQUE REFERENCES venues (id) ON DELETE RESTRICT,
    stripe_customer_id TEXT NOT NULL UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE TABLE venue_subscriptions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL UNIQUE REFERENCES venues (id) ON DELETE RESTRICT,
    stripe_subscription_id TEXT NOT NULL UNIQUE,
    stripe_price_id TEXT NOT NULL,
    status TEXT NOT NULL,
    current_period_start TIMESTAMP WITH TIME ZONE,
    current_period_end TIMESTAMP WITH TIME ZONE,
    cancel_at_period_end BOOLEAN DEFAULT FALSE NOT NULL,
    last_synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE TABLE billing_events (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    stripe_event_id TEXT NOT NULL UNIQUE,
    event_type TEXT NOT NULL,
    livemode BOOLEAN DEFAULT FALSE NOT NULL,
    received_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    processed_at TIMESTAMP WITH TIME ZONE,
    status TEXT NOT NULL,
    error_summary TEXT,
    venue_id UUID REFERENCES venues (id) ON DELETE SET NULL,
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    provider_object_type TEXT,
    provider_object_id TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

INSERT INTO users (id) VALUES ('a0000000-0000-0000-0000-000000000001');
INSERT INTO venues (id, name) VALUES ('a1000000-0000-0000-0000-000000000001', 'Preserved Venue');
INSERT INTO venue_billing_customers (venue_id, stripe_customer_id)
VALUES ('a1000000-0000-0000-0000-000000000001', 'cus_preserved');
INSERT INTO venue_subscriptions (venue_id, stripe_subscription_id, stripe_price_id, status)
VALUES ('a1000000-0000-0000-0000-000000000001', 'sub_preserved', 'price_preserved', 'active');
INSERT INTO billing_events (stripe_event_id, event_type, status, venue_id, stripe_customer_id, stripe_subscription_id)
VALUES ('evt_preserved', 'customer.subscription.updated', 'processed', 'a1000000-0000-0000-0000-000000000001', 'cus_preserved', 'sub_preserved');
