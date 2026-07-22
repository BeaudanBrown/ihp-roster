-- Add the durable billing state required for production Checkout recovery and
-- ordered Stripe subscription updates. Existing billing rows predate live
-- billing, so the constant FALSE defaults are the explicit safe test-mode
-- backfill. Unknown legacy creator/event-order metadata intentionally remains
-- NULL rather than inventing audit provenance or provider timestamps.

ALTER TABLE venue_billing_customers
    ADD COLUMN livemode BOOLEAN DEFAULT FALSE NOT NULL,
    ADD COLUMN created_by_user_id UUID DEFAULT NULL,
    ADD FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE venue_billing_customers
    ALTER COLUMN livemode DROP DEFAULT;

CREATE TABLE billing_checkout_attempts (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    initiated_by_user_id UUID NOT NULL,
    livemode BOOLEAN NOT NULL,
    stripe_customer_id TEXT NOT NULL,
    stripe_price_id TEXT NOT NULL,
    stripe_checkout_session_id TEXT DEFAULT NULL,
    stripe_subscription_id TEXT DEFAULT NULL,
    status TEXT DEFAULT 'open' NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    completed_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    error_code TEXT DEFAULT NULL,
    error_summary TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(stripe_checkout_session_id),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (initiated_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((status = 'open') OR (status = 'completed') OR (status = 'expired') OR (status = 'failed')),
    CHECK (((status = 'completed') AND completed_at IS NOT NULL AND stripe_checkout_session_id IS NOT NULL) OR ((status <> 'completed') AND completed_at IS NULL)),
    CHECK ((char_length(btrim(stripe_customer_id)) > 0) AND (char_length(stripe_customer_id) <= 255)),
    CHECK ((char_length(btrim(stripe_price_id)) > 0) AND (char_length(stripe_price_id) <= 255)),
    CHECK (stripe_checkout_session_id IS NULL OR ((char_length(btrim(stripe_checkout_session_id)) > 0) AND (char_length(stripe_checkout_session_id) <= 255))),
    CHECK (stripe_subscription_id IS NULL OR ((char_length(btrim(stripe_subscription_id)) > 0) AND (char_length(stripe_subscription_id) <= 255))),
    CHECK (error_code IS NULL OR ((char_length(btrim(error_code)) > 0) AND (char_length(error_code) <= 120))),
    CHECK (error_summary IS NULL OR ((char_length(btrim(error_summary)) > 0) AND (char_length(error_summary) <= 1000)))
);

ALTER TABLE venue_subscriptions
    ADD COLUMN livemode BOOLEAN DEFAULT FALSE NOT NULL,
    ADD COLUMN last_applied_stripe_event_created_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN last_applied_stripe_event_id TEXT DEFAULT NULL,
    ADD CHECK ((last_applied_stripe_event_created_at IS NULL AND last_applied_stripe_event_id IS NULL) OR (last_applied_stripe_event_created_at IS NOT NULL AND last_applied_stripe_event_id IS NOT NULL)),
    ADD CHECK (last_applied_stripe_event_id IS NULL OR ((char_length(btrim(last_applied_stripe_event_id)) > 0) AND (char_length(last_applied_stripe_event_id) <= 255)));

ALTER TABLE venue_subscriptions
    ALTER COLUMN livemode DROP DEFAULT;

ALTER TABLE billing_events
    ADD COLUMN stripe_created_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;

ALTER TABLE billing_events
    ALTER COLUMN livemode DROP DEFAULT;

CREATE UNIQUE INDEX idx_billing_checkout_attempts_one_open_per_venue
    ON billing_checkout_attempts (venue_id)
    WHERE status = 'open';

CREATE INDEX idx_billing_checkout_attempts_venue_created_at
    ON billing_checkout_attempts (venue_id, created_at DESC);

CREATE INDEX idx_billing_checkout_attempts_subscription
    ON billing_checkout_attempts (stripe_subscription_id)
    WHERE stripe_subscription_id IS NOT NULL;

CREATE INDEX idx_billing_events_stripe_created_at
    ON billing_events (stripe_created_at, stripe_event_id)
    WHERE stripe_created_at IS NOT NULL;
