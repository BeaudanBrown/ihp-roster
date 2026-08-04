-- GitHub #313: retained immutable roster notification run snapshots and related delivery-job lookup.
CREATE TABLE roster_notification_runs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    roster_group_id UUID NOT NULL,
    roster_week_id UUID NOT NULL,
    week_offset INT NOT NULL,
    week_start DATE NOT NULL,
    snapshot_schema_version INT DEFAULT 1 NOT NULL,
    roster_snapshot JSONB NOT NULL,
    recipient_snapshot JSONB NOT NULL,
    skipped_recipient_snapshot JSONB NOT NULL,
    requested_by_user_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (roster_group_id) REFERENCES roster_groups (id) ON DELETE RESTRICT,
    FOREIGN KEY (roster_week_id) REFERENCES roster_weeks (id) ON DELETE RESTRICT,
    FOREIGN KEY (requested_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK (snapshot_schema_version > 0),
    CHECK (jsonb_typeof(roster_snapshot) = 'object'),
    CHECK (jsonb_typeof(recipient_snapshot) = 'array'),
    CHECK (jsonb_typeof(skipped_recipient_snapshot) = 'array')
);

CREATE INDEX IF NOT EXISTS idx_roster_notification_runs_group_week_created
    ON roster_notification_runs (roster_group_id, week_offset, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_app_jobs_related ON app_jobs (related_table, related_id);

CREATE OR REPLACE FUNCTION enforce_roster_notification_run_immutability()
RETURNS TRIGGER
AS $$
BEGIN
    RAISE EXCEPTION 'roster notification runs are immutable retained communication records';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS enforce_roster_notification_runs_immutable ON roster_notification_runs;
CREATE TRIGGER enforce_roster_notification_runs_immutable
    BEFORE UPDATE OR DELETE ON roster_notification_runs
    FOR EACH ROW EXECUTE FUNCTION enforce_roster_notification_run_immutability();
