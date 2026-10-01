-- Add provider correlation and bounded webhook/audited-resend history.
-- Historical successful SMTP jobs remain provider_status=unknown by design.
CREATE TABLE email_delivery_provider_states (
    email_delivery_job_id UUID PRIMARY KEY NOT NULL,
    message_id TEXT NOT NULL,
    provider_email_id TEXT DEFAULT NULL,
    smtp_accepted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    provider_status TEXT DEFAULT 'unknown' NOT NULL,
    provider_status_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE (message_id),
    UNIQUE (provider_email_id),
    FOREIGN KEY (email_delivery_job_id) REFERENCES app_jobs (id) ON DELETE RESTRICT,
    CHECK ((provider_status = 'unknown') OR (provider_status = 'delivered') OR (provider_status = 'bounced') OR (provider_status = 'complained') OR (provider_status = 'failed') OR (provider_status = 'suppressed')),
    CHECK ((char_length(message_id) >= 3) AND (char_length(message_id) <= 320)),
    CHECK (provider_email_id IS NULL OR char_length(provider_email_id) <= 160)
);
CREATE TABLE email_delivery_webhook_events (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    svix_id TEXT NOT NULL,
    signature_timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    event_type TEXT NOT NULL,
    provider_email_id TEXT NOT NULL,
    message_id TEXT DEFAULT NULL,
    event_at TIMESTAMP WITH TIME ZONE NOT NULL,
    received_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    processing_outcome TEXT NOT NULL,
    UNIQUE (svix_id),
    CHECK ((event_type = 'email.sent') OR (event_type = 'email.delivered') OR (event_type = 'email.bounced') OR (event_type = 'email.complained') OR (event_type = 'email.failed') OR (event_type = 'email.suppressed')),
    CHECK ((processing_outcome = 'correlated') OR (processing_outcome = 'unknown_message') OR (processing_outcome = 'ignored_older_status')),
    CHECK ((char_length(svix_id) >= 1) AND (char_length(svix_id) <= 160)),
    CHECK ((char_length(provider_email_id) >= 1) AND (char_length(provider_email_id) <= 160)),
    CHECK (message_id IS NULL OR char_length(message_id) <= 320)
);
CREATE TABLE email_delivery_resend_requests (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    original_email_delivery_job_id UUID NOT NULL,
    replacement_email_delivery_job_id UUID DEFAULT NULL,
    requested_by_user_id UUID NOT NULL,
    reason TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE (replacement_email_delivery_job_id),
    FOREIGN KEY (original_email_delivery_job_id) REFERENCES app_jobs (id) ON DELETE RESTRICT,
    FOREIGN KEY (replacement_email_delivery_job_id) REFERENCES app_jobs (id) ON DELETE RESTRICT,
    FOREIGN KEY (requested_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((char_length(reason) >= 1) AND (char_length(reason) <= 240))
);
