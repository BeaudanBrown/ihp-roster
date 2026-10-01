-- Host-local watchdog least-privilege database boundary and application projection.
-- Additive only: existing jobs, incidents and deliveries are preserved.

CREATE TABLE host_watchdog_dispatches (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    operational_incident_event_id UUID NOT NULL,
    recipient_address_digest TEXT NOT NULL,
    dispatch_status TEXT NOT NULL,
    provider_email_id TEXT DEFAULT NULL,
    attempted_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE (operational_incident_event_id, recipient_address_digest),
    FOREIGN KEY (operational_incident_event_id) REFERENCES operational_incident_events (id) ON DELETE RESTRICT,
    CHECK (char_length(recipient_address_digest) = 64),
    CHECK ((dispatch_status = 'sent') OR (dispatch_status = 'failed')),
    CHECK (provider_email_id IS NULL OR char_length(provider_email_id) <= 160)
);

CREATE OR REPLACE FUNCTION bepis_watchdog_poll()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    snapshot JSONB;
BEGIN
    IF session_user <> 'bepis_watchdog' THEN
        RAISE EXCEPTION 'watchdog database role required';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.app_jobs
        WHERE job_kind = 'worker_heartbeat'
          AND status IN ('job_status_not_started', 'job_status_retry', 'job_status_running')
          AND created_at >= clock_timestamp() - INTERVAL '1 minute'
    ) THEN
        INSERT INTO public.app_jobs (job_kind, payload, dedupe_key, run_at)
        VALUES ('worker_heartbeat', '{"source":"host_watchdog"}'::JSONB, 'host-watchdog-heartbeat:' || floor(extract(epoch FROM clock_timestamp()) / 60)::TEXT, clock_timestamp())
        ON CONFLICT DO NOTHING;
    END IF;

    SELECT jsonb_build_object(
        'observedAt', clock_timestamp(),
        'eligibleRecipients', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('userId', id, 'address', email) ORDER BY id)
            FROM public.users
            WHERE platform_role = 'super_admin' AND deactivated_at IS NULL
        ), '[]'::JSONB),
        'latestWorkerHeartbeatAt', (
            SELECT max(updated_at) FROM public.app_jobs
            WHERE job_kind = 'worker_heartbeat' AND status = 'job_status_succeeded'
        ),
        'overdueRunnableJobCount', (
            SELECT count(*) FROM public.app_jobs
            WHERE status IN ('job_status_not_started', 'job_status_retry')
              AND run_at <= clock_timestamp() - INTERVAL '5 minutes'
        ),
        'recentEmailFailureCount', (
            SELECT count(*)
            FROM public.app_jobs jobs
            LEFT JOIN public.email_delivery_provider_states provider
              ON provider.email_delivery_job_id = jobs.id
            WHERE jobs.job_kind = 'email_delivery'
              AND jobs.updated_at >= clock_timestamp() - INTERVAL '24 hours'
              AND (
                jobs.status IN ('job_status_failed', 'job_status_timed_out')
                OR provider.provider_status IN ('bounced', 'complained', 'failed', 'suppressed')
              )
        )
    ) INTO snapshot;
    RETURN snapshot;
END;
$$;

CREATE OR REPLACE FUNCTION bepis_watchdog_record_event(p_event_key TEXT, p_category TEXT, p_stable_identity TEXT, p_transition TEXT, p_observed_at TIMESTAMP WITH TIME ZONE, p_severity TEXT, p_impact_key TEXT, p_impact_rank INT, p_symptom_codes JSONB, p_safe_metadata JSONB, p_notification_required BOOLEAN, p_eligible_recipient_count INT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    incident_id UUID;
    next_sequence INT;
    effective_transition TEXT := p_transition;
BEGIN
    IF session_user <> 'bepis_watchdog' THEN
        RAISE EXCEPTION 'watchdog database role required';
    END IF;
    IF p_event_key IS NULL OR char_length(p_event_key) NOT BETWEEN 1 AND 320
       OR p_category IS NULL OR char_length(p_category) NOT BETWEEN 1 AND 80
       OR p_stable_identity IS NULL OR char_length(p_stable_identity) NOT BETWEEN 1 AND 240
       OR p_transition NOT IN ('opened', 'impact_escalated', 'recovered', 'recurred')
       OR p_severity NOT IN ('info', 'warning', 'critical')
       OR p_impact_rank NOT BETWEEN 0 AND 100
       OR jsonb_typeof(p_symptom_codes) <> 'array' OR octet_length(p_symptom_codes::TEXT) > 2048
       OR jsonb_typeof(p_safe_metadata) <> 'object' OR octet_length(p_safe_metadata::TEXT) > 4096
       OR p_eligible_recipient_count < 0 THEN
        RAISE EXCEPTION 'invalid bounded watchdog event';
    END IF;

    IF EXISTS (SELECT 1 FROM public.operational_incident_events WHERE event_key = p_event_key) THEN
        RETURN;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('host-watchdog:' || p_category || ':' || p_stable_identity, 0));
    SELECT id INTO incident_id
    FROM public.operational_incidents
    WHERE category = p_category AND scope_key = 'host:rozzy' AND stable_identity = p_stable_identity
    FOR UPDATE;

    IF incident_id IS NULL THEN
        IF p_transition = 'recovered' THEN
            RETURN;
        END IF;
        effective_transition := 'opened';
        INSERT INTO public.operational_incidents (
            category, scope_key, stable_identity, affected_source, first_observed_at,
            last_observed_at, opened_at, state, severity, impact_key, impact_rank,
            symptom_codes, safe_metadata
        ) VALUES (
            p_category, 'host:rozzy', p_stable_identity, 'host_watchdog', p_observed_at,
            p_observed_at, p_observed_at, 'open', p_severity, p_impact_key, p_impact_rank,
            p_symptom_codes, p_safe_metadata
        ) RETURNING id INTO incident_id;
    ELSIF p_transition = 'recovered' THEN
        UPDATE public.operational_incidents
        SET state = 'resolved', resolved_at = p_observed_at, last_observed_at = p_observed_at,
            symptom_codes = p_symptom_codes, safe_metadata = p_safe_metadata, updated_at = clock_timestamp()
        WHERE id = incident_id AND state = 'open';
    ELSIF p_transition = 'recurred' THEN
        UPDATE public.operational_incidents
        SET state = 'open', resolved_at = NULL, opened_at = p_observed_at,
            last_observed_at = p_observed_at, severity = p_severity, impact_key = p_impact_key,
            impact_rank = p_impact_rank, symptom_codes = p_symptom_codes,
            safe_metadata = p_safe_metadata, occurrence_count = occurrence_count + 1,
            updated_at = clock_timestamp()
        WHERE id = incident_id;
    ELSE
        UPDATE public.operational_incidents
        SET last_observed_at = p_observed_at, severity = p_severity, impact_key = p_impact_key,
            impact_rank = greatest(impact_rank, p_impact_rank), symptom_codes = p_symptom_codes,
            safe_metadata = p_safe_metadata, updated_at = clock_timestamp()
        WHERE id = incident_id;
    END IF;

    SELECT COALESCE(max(event_sequence), 0) + 1 INTO next_sequence
    FROM public.operational_incident_events WHERE operational_incident_id = incident_id;

    INSERT INTO public.operational_incident_events (
        operational_incident_id, event_sequence, transition, event_key, observed_at,
        severity, impact_key, symptom_codes, safe_metadata, notification_required,
        eligible_recipient_count, recipients_reconciled_at
    ) VALUES (
        incident_id, next_sequence, effective_transition, p_event_key, p_observed_at,
        p_severity, p_impact_key, p_symptom_codes, p_safe_metadata, p_notification_required,
        p_eligible_recipient_count, p_observed_at
    ) ON CONFLICT (event_key) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION bepis_watchdog_record_dispatch(p_event_key TEXT, p_recipient_address_digest TEXT, p_dispatch_status TEXT, p_provider_email_id TEXT, p_attempted_at TIMESTAMP WITH TIME ZONE)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF session_user <> 'bepis_watchdog' THEN
        RAISE EXCEPTION 'watchdog database role required';
    END IF;
    IF char_length(p_recipient_address_digest) <> 64
       OR p_dispatch_status NOT IN ('sent', 'failed')
       OR (p_provider_email_id IS NOT NULL AND char_length(p_provider_email_id) > 160) THEN
        RAISE EXCEPTION 'invalid bounded watchdog dispatch';
    END IF;
    INSERT INTO public.host_watchdog_dispatches (
        operational_incident_event_id, recipient_address_digest, dispatch_status,
        provider_email_id, attempted_at
    )
    SELECT id, p_recipient_address_digest, p_dispatch_status, p_provider_email_id, p_attempted_at
    FROM public.operational_incident_events WHERE event_key = p_event_key
    ON CONFLICT (operational_incident_event_id, recipient_address_digest) DO UPDATE
    SET dispatch_status = EXCLUDED.dispatch_status,
        provider_email_id = COALESCE(EXCLUDED.provider_email_id, host_watchdog_dispatches.provider_email_id),
        attempted_at = EXCLUDED.attempted_at,
        updated_at = clock_timestamp();
END;
$$;

REVOKE ALL ON FUNCTION bepis_watchdog_poll() FROM PUBLIC;
REVOKE ALL ON FUNCTION bepis_watchdog_record_event(TEXT, TEXT, TEXT, TEXT, TIMESTAMP WITH TIME ZONE, TEXT, TEXT, INT, JSONB, JSONB, BOOLEAN, INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION bepis_watchdog_record_dispatch(TEXT, TEXT, TEXT, TEXT, TIMESTAMP WITH TIME ZONE) FROM PUBLIC;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bepis_watchdog') THEN
        GRANT EXECUTE ON FUNCTION bepis_watchdog_poll() TO bepis_watchdog;
        GRANT EXECUTE ON FUNCTION bepis_watchdog_record_event(TEXT, TEXT, TEXT, TEXT, TIMESTAMP WITH TIME ZONE, TEXT, TEXT, INT, JSONB, JSONB, BOOLEAN, INT) TO bepis_watchdog;
        GRANT EXECUTE ON FUNCTION bepis_watchdog_record_dispatch(TEXT, TEXT, TEXT, TEXT, TIMESTAMP WITH TIME ZONE) TO bepis_watchdog;
    END IF;
END;
$$;
