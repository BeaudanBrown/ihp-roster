-- Bounded host backup/restore-verification status projected by the watchdog.
-- No backup contents, repository credentials, or snapshot identifiers are stored.
CREATE TABLE host_watchdog_statuses (
    host_name TEXT PRIMARY KEY NOT NULL,
    observed_at TIMESTAMP WITH TIME ZONE NOT NULL,
    last_backup_snapshot_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    last_restore_verified_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    backup_result TEXT NOT NULL,
    verification_result TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CHECK (host_name = 'rozzy'),
    CHECK ((char_length(backup_result) >= 1) AND (char_length(backup_result) <= 80)),
    CHECK ((char_length(verification_result) >= 1) AND (char_length(verification_result) <= 80))
);

CREATE OR REPLACE FUNCTION bepis_watchdog_record_status(p_status JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    observed TIMESTAMP WITH TIME ZONE;
    backup_snapshot TIMESTAMP WITH TIME ZONE;
    restore_verified TIMESTAMP WITH TIME ZONE;
    backup_state TEXT;
    verification_state TEXT;
BEGIN
    IF session_user <> 'bepis_watchdog' THEN
        RAISE EXCEPTION 'watchdog database role required';
    END IF;
    IF jsonb_typeof(p_status) <> 'object' OR octet_length(p_status::TEXT) > 2048 THEN
        RAISE EXCEPTION 'invalid bounded watchdog status';
    END IF;
    observed := (p_status ->> 'observedAt')::TIMESTAMP WITH TIME ZONE;
    backup_snapshot := NULLIF(p_status ->> 'lastBackupSnapshotAt', '')::TIMESTAMP WITH TIME ZONE;
    restore_verified := NULLIF(p_status ->> 'lastRestoreVerifiedAt', '')::TIMESTAMP WITH TIME ZONE;
    backup_state := p_status ->> 'backupResult';
    verification_state := p_status ->> 'verificationResult';
    IF observed IS NULL OR backup_state IS NULL OR char_length(backup_state) NOT BETWEEN 1 AND 80
       OR verification_state IS NULL OR char_length(verification_state) NOT BETWEEN 1 AND 80 THEN
        RAISE EXCEPTION 'invalid bounded watchdog status';
    END IF;
    INSERT INTO public.host_watchdog_statuses (
        host_name, observed_at, last_backup_snapshot_at, last_restore_verified_at,
        backup_result, verification_result
    ) VALUES (
        'rozzy', observed, backup_snapshot, restore_verified, backup_state, verification_state
    )
    ON CONFLICT (host_name) DO UPDATE SET
        observed_at = EXCLUDED.observed_at,
        last_backup_snapshot_at = EXCLUDED.last_backup_snapshot_at,
        last_restore_verified_at = EXCLUDED.last_restore_verified_at,
        backup_result = EXCLUDED.backup_result,
        verification_result = EXCLUDED.verification_result,
        updated_at = clock_timestamp();
END;
$$;

REVOKE ALL ON FUNCTION bepis_watchdog_record_status(JSONB) FROM PUBLIC;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bepis_watchdog') THEN
        GRANT EXECUTE ON FUNCTION bepis_watchdog_record_status(JSONB) TO bepis_watchdog;
    END IF;
END;
$$;
