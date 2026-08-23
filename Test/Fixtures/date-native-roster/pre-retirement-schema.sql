CREATE TABLE roster_groups (
    id UUID PRIMARY KEY,
    venue_id UUID NOT NULL
);

CREATE TABLE roster_weeks (
    id UUID PRIMARY KEY,
    venue_id UUID NOT NULL,
    roster_group_id UUID NOT NULL REFERENCES roster_groups (id),
    week_offset INT NOT NULL,
    is_live BOOLEAN NOT NULL
);

CREATE TABLE venue_config (
    id UUID PRIMARY KEY,
    venue_id UUID NOT NULL,
    week_offset_epoch DATE NOT NULL
);

CREATE TABLE roster_days (
    id UUID PRIMARY KEY,
    roster_week_id UUID REFERENCES roster_weeks (id),
    venue_id UUID NOT NULL,
    roster_group_id UUID NOT NULL REFERENCES roster_groups (id),
    operational_date DATE NOT NULL,
    publication_state TEXT NOT NULL,
    day_offset INT
);

CREATE TABLE roster_week_slot_definitions (
    id UUID PRIMARY KEY,
    roster_week_id UUID NOT NULL REFERENCES roster_weeks (id)
);

CREATE TABLE roster_lanes (
    id UUID PRIMARY KEY,
    roster_day_id UUID NOT NULL REFERENCES roster_days (id),
    legacy_roster_week_slot_definition_id UUID REFERENCES roster_week_slot_definitions (id),
    name TEXT NOT NULL
);

CREATE TABLE roster_slots (
    id UUID PRIMARY KEY,
    roster_day_id UUID NOT NULL REFERENCES roster_days (id),
    roster_lane_id UUID NOT NULL REFERENCES roster_lanes (id),
    roster_week_slot_definition_id UUID REFERENCES roster_week_slot_definitions (id),
    starts_at TIMESTAMPTZ,
    ends_at TIMESTAMPTZ
);

CREATE TABLE roster_notification_runs (
    id UUID PRIMARY KEY,
    roster_week_id UUID REFERENCES roster_weeks (id),
    week_offset INT,
    week_start DATE NOT NULL,
    window_end DATE NOT NULL,
    roster_snapshot JSONB NOT NULL
);

CREATE TABLE timesheet_entries (
    id UUID PRIMARY KEY,
    source_roster_slot_id UUID REFERENCES roster_slots (id) ON DELETE RESTRICT,
    operational_date DATE NOT NULL
);

CREATE TABLE export_job_entries (
    id UUID PRIMARY KEY,
    source_roster_slot_id UUID REFERENCES roster_slots (id) ON DELETE RESTRICT,
    row_snapshot JSONB NOT NULL
);

CREATE FUNCTION project_legacy_roster_slot_lane() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;
CREATE FUNCTION project_legacy_roster_day_lanes() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;
CREATE FUNCTION project_legacy_roster_week_definition_lanes() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;
CREATE FUNCTION project_legacy_roster_lane(UUID, UUID) RETURNS UUID AS $$ SELECT $2; $$ LANGUAGE sql;
CREATE FUNCTION project_legacy_roster_day() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;
CREATE FUNCTION prevent_legacy_roster_lane_identity_change() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;
CREATE FUNCTION prevent_legacy_roster_definition_week_change() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;
CREATE FUNCTION refresh_legacy_roster_week_day_projections() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;
CREATE FUNCTION enforce_roster_week_venue_integrity() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;
CREATE FUNCTION validate_roster_lane_scope() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;
CREATE FUNCTION prevent_hard_delete_fixture() RETURNS TRIGGER AS $$ BEGIN RETURN OLD; END; $$ LANGUAGE plpgsql;

CREATE TRIGGER project_legacy_roster_slot_lane BEFORE INSERT OR UPDATE ON roster_slots FOR EACH ROW EXECUTE FUNCTION project_legacy_roster_slot_lane();
CREATE TRIGGER prevent_legacy_roster_lane_identity_change BEFORE UPDATE ON roster_lanes FOR EACH ROW EXECUTE FUNCTION prevent_legacy_roster_lane_identity_change();
CREATE TRIGGER validate_roster_lane_scope BEFORE INSERT OR UPDATE ON roster_lanes FOR EACH ROW EXECUTE FUNCTION validate_roster_lane_scope();
CREATE TRIGGER project_legacy_roster_day_lanes AFTER INSERT OR UPDATE ON roster_days FOR EACH ROW EXECUTE FUNCTION project_legacy_roster_day_lanes();
CREATE TRIGGER project_legacy_roster_day BEFORE INSERT OR UPDATE ON roster_days FOR EACH ROW EXECUTE FUNCTION project_legacy_roster_day();
CREATE TRIGGER project_legacy_roster_week_definition_lanes AFTER INSERT OR UPDATE ON roster_week_slot_definitions FOR EACH ROW EXECUTE FUNCTION project_legacy_roster_week_definition_lanes();
CREATE TRIGGER prevent_legacy_roster_definition_week_change BEFORE UPDATE ON roster_week_slot_definitions FOR EACH ROW EXECUTE FUNCTION prevent_legacy_roster_definition_week_change();
CREATE TRIGGER refresh_legacy_roster_week_day_projections AFTER UPDATE ON roster_weeks FOR EACH ROW EXECUTE FUNCTION refresh_legacy_roster_week_day_projections();
CREATE TRIGGER enforce_roster_week_venue_integrity BEFORE INSERT OR UPDATE ON roster_weeks FOR EACH ROW EXECUTE FUNCTION enforce_roster_week_venue_integrity();
CREATE TRIGGER prevent_hard_delete_roster_weeks BEFORE DELETE ON roster_weeks FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete_fixture();

INSERT INTO roster_groups VALUES ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001');
INSERT INTO roster_weeks VALUES ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 4, TRUE);
INSERT INTO venue_config VALUES ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '2026-07-06');
INSERT INTO roster_days VALUES ('50000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '2026-08-03', 'published', 0);
INSERT INTO roster_week_slot_definitions VALUES ('60000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001');
INSERT INTO roster_lanes VALUES ('70000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 'Early');
INSERT INTO roster_slots VALUES ('80000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', '2026-08-02 23:00:00+00', '2026-08-03 07:00:00+00');
INSERT INTO roster_notification_runs VALUES ('90000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 4, '2026-08-03', '2026-08-10', '{"weekStart":"2026-08-03","weekEnd":"2026-08-09","shifts":[]}');
INSERT INTO timesheet_entries VALUES ('a0000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001', '2026-08-03');
INSERT INTO export_job_entries VALUES ('b0000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001', '{"operationalDate":"2026-08-03"}');
