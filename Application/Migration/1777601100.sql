CREATE TABLE IF NOT EXISTS venue_billing_customers (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    stripe_customer_id TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(venue_id),
    UNIQUE(stripe_customer_id),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    CHECK ((char_length(btrim(stripe_customer_id)) > 0) AND (char_length(stripe_customer_id) <= 255))
);

CREATE TABLE IF NOT EXISTS venue_subscriptions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    stripe_subscription_id TEXT NOT NULL,
    stripe_price_id TEXT NOT NULL,
    status TEXT NOT NULL,
    current_period_start TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    current_period_end TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    cancel_at_period_end BOOLEAN DEFAULT FALSE NOT NULL,
    last_synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(venue_id),
    UNIQUE(stripe_subscription_id),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    CHECK ((char_length(btrim(stripe_subscription_id)) > 0) AND (char_length(stripe_subscription_id) <= 255)),
    CHECK ((char_length(btrim(stripe_price_id)) > 0) AND (char_length(stripe_price_id) <= 255)),
    CHECK ((status = 'incomplete') OR (status = 'incomplete_expired') OR (status = 'trialing') OR (status = 'active') OR (status = 'past_due') OR (status = 'canceled') OR (status = 'unpaid') OR (status = 'paused')),
    CHECK (current_period_start IS NULL OR current_period_end IS NULL OR current_period_start <= current_period_end)
);

CREATE TABLE IF NOT EXISTS billing_events (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    stripe_event_id TEXT NOT NULL,
    event_type TEXT NOT NULL,
    livemode BOOLEAN DEFAULT FALSE NOT NULL,
    api_version TEXT DEFAULT NULL,
    provider_object_type TEXT DEFAULT NULL,
    provider_object_id TEXT DEFAULT NULL,
    venue_id UUID DEFAULT NULL,
    stripe_customer_id TEXT DEFAULT NULL,
    stripe_subscription_id TEXT DEFAULT NULL,
    status TEXT DEFAULT 'received' NOT NULL,
    error_summary TEXT DEFAULT NULL,
    received_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    processed_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(stripe_event_id),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    CHECK ((char_length(btrim(stripe_event_id)) > 0) AND (char_length(stripe_event_id) <= 255)),
    CHECK ((char_length(btrim(event_type)) > 0) AND (char_length(event_type) <= 255)),
    CHECK (api_version IS NULL OR ((char_length(btrim(api_version)) > 0) AND (char_length(api_version) <= 80))),
    CHECK (provider_object_type IS NULL OR ((char_length(btrim(provider_object_type)) > 0) AND (char_length(provider_object_type) <= 120))),
    CHECK (provider_object_id IS NULL OR ((char_length(btrim(provider_object_id)) > 0) AND (char_length(provider_object_id) <= 255))),
    CHECK (stripe_customer_id IS NULL OR ((char_length(btrim(stripe_customer_id)) > 0) AND (char_length(stripe_customer_id) <= 255))),
    CHECK (stripe_subscription_id IS NULL OR ((char_length(btrim(stripe_subscription_id)) > 0) AND (char_length(stripe_subscription_id) <= 255))),
    CHECK ((status = 'received') OR (status = 'processed') OR (status = 'failed') OR (status = 'ignored')),
    CHECK (error_summary IS NULL OR ((char_length(btrim(error_summary)) > 0) AND (char_length(error_summary) <= 1000))),
    CHECK (((status = 'processed') AND processed_at IS NOT NULL) OR (status <> 'processed'))
);

CREATE TABLE IF NOT EXISTS venue_billing_controls (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    billing_required BOOLEAN DEFAULT TRUE NOT NULL,
    manual_read_only BOOLEAN DEFAULT FALSE NOT NULL,
    manual_read_only_reason TEXT DEFAULT NULL,
    set_by_user_id UUID DEFAULT NULL,
    set_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(venue_id),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (set_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK (manual_read_only_reason IS NULL OR ((char_length(btrim(manual_read_only_reason)) > 0) AND (char_length(manual_read_only_reason) <= 500))),
    CHECK ((set_by_user_id IS NULL AND set_at IS NULL) OR (set_by_user_id IS NOT NULL AND set_at IS NOT NULL)),
    CHECK ((manual_read_only = FALSE) OR (manual_read_only_reason IS NOT NULL AND set_by_user_id IS NOT NULL AND set_at IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS idx_venue_billing_customers_venue ON venue_billing_customers (venue_id);
CREATE INDEX IF NOT EXISTS idx_venue_subscriptions_venue_status ON venue_subscriptions (venue_id, status);
CREATE INDEX IF NOT EXISTS idx_billing_events_received_at ON billing_events (received_at DESC);
CREATE INDEX IF NOT EXISTS idx_billing_events_status_received_at ON billing_events (status, received_at);
CREATE INDEX IF NOT EXISTS idx_billing_events_venue_received_at ON billing_events (venue_id, received_at DESC) WHERE venue_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_billing_events_provider_object ON billing_events (provider_object_type, provider_object_id) WHERE provider_object_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_venue_billing_controls_manual_read_only ON venue_billing_controls (manual_read_only) WHERE manual_read_only = TRUE;
