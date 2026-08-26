DROP SCHEMA IF EXISTS date_native_roster_migration_acceptance CASCADE;
CREATE SCHEMA date_native_roster_migration_acceptance;
SET LOCAL search_path TO date_native_roster_migration_acceptance, public;

CREATE TABLE venues (id UUID PRIMARY KEY);
CREATE TABLE users (id UUID PRIMARY KEY);
CREATE TABLE roster_groups (
    id UUID PRIMARY KEY,
    venue_id UUID NOT NULL REFERENCES venues (id)
);
CREATE TABLE venue_config (
    id UUID PRIMARY KEY,
    venue_id UUID NOT NULL UNIQUE REFERENCES venues (id),
    roster_week_starts_on INT NOT NULL,
    week_offset_epoch DATE NOT NULL
);
CREATE TABLE roster_weeks (
    id UUID PRIMARY KEY,
    venue_id UUID NOT NULL REFERENCES venues (id),
    roster_group_id UUID NOT NULL REFERENCES roster_groups (id),
    week_offset INT NOT NULL,
    is_live BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE roster_days (
    id UUID PRIMARY KEY,
    roster_week_id UUID NOT NULL REFERENCES roster_weeks (id),
    day_offset INT NOT NULL,
    is_closed BOOLEAN DEFAULT FALSE NOT NULL,
    row_count INT DEFAULT 4 NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    UNIQUE(roster_week_id, day_offset)
);
CREATE TABLE roster_week_slot_definitions (
    id UUID PRIMARY KEY,
    roster_week_id UUID NOT NULL REFERENCES roster_weeks (id),
    name TEXT NOT NULL,
    sort_order INT NOT NULL,
    deleted_at TIMESTAMPTZ,
    deleted_by_user_id UUID REFERENCES users (id),
    delete_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE staff (
    id UUID PRIMARY KEY,
    venue_id UUID NOT NULL REFERENCES venues (id)
);
CREATE TABLE shift_types (
    id UUID PRIMARY KEY,
    venue_id UUID NOT NULL REFERENCES venues (id)
);
CREATE TABLE roster_slots (
    id UUID PRIMARY KEY,
    roster_day_id UUID NOT NULL REFERENCES roster_days (id),
    assignment_state TEXT NOT NULL,
    staff_id UUID REFERENCES staff (id),
    roster_week_slot_definition_id UUID NOT NULL REFERENCES roster_week_slot_definitions (id),
    slot_sort_order INT DEFAULT 0 NOT NULL,
    row_index INT NOT NULL,
    starts_at TIMESTAMPTZ,
    ends_at TIMESTAMPTZ,
    timezone TEXT NOT NULL,
    shift_type_id UUID REFERENCES shift_types (id),
    deleted_at TIMESTAMPTZ,
    deleted_by_user_id UUID REFERENCES users (id),
    delete_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE OR REPLACE FUNCTION prevent_hard_delete()
RETURNS TRIGGER AS $$ BEGIN RAISE EXCEPTION 'hard delete blocked'; END; $$ LANGUAGE plpgsql;

INSERT INTO venues (id) VALUES ('10000000-0000-0000-0000-000000000001');
INSERT INTO users (id) VALUES ('20000000-0000-0000-0000-000000000001');
INSERT INTO roster_groups (id, venue_id)
VALUES ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001');
INSERT INTO venue_config (id, venue_id, roster_week_starts_on, week_offset_epoch)
VALUES ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 1, '2026-08-03');
INSERT INTO roster_weeks (id, venue_id, roster_group_id, week_offset, is_live, created_at, updated_at)
VALUES ('50000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 0, TRUE, '2026-06-01 00:00:00+00', '2026-06-02 00:00:00+00');
INSERT INTO roster_days (id, roster_week_id, day_offset, created_at, updated_at)
SELECT
    md5('foundation-day-' || day_offset::text)::uuid,
    '50000000-0000-0000-0000-000000000001',
    day_offset,
    '2026-07-01 00:00:00+00',
    '2026-07-02 00:00:00+00'
FROM generate_series(0, 5) AS offsets(day_offset);
INSERT INTO roster_week_slot_definitions (
    id, roster_week_id, name, sort_order, deleted_at, deleted_by_user_id,
    delete_reason, created_at, updated_at
) VALUES
    ('60000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', 'Floor', 0, NULL, NULL, NULL, '2026-07-03 00:00:00+00', '2026-07-04 00:00:00+00'),
    ('60000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000001', 'Retained bar', 1, '2026-07-05 00:00:00+00', '20000000-0000-0000-0000-000000000001', 'layout changed', '2026-07-03 00:00:00+00', '2026-07-05 00:00:00+00');
INSERT INTO staff (id, venue_id)
VALUES ('70000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001');
INSERT INTO shift_types (id, venue_id)
VALUES ('80000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001');
INSERT INTO roster_slots (
    id, roster_day_id, assignment_state, staff_id,
    roster_week_slot_definition_id, slot_sort_order, row_index, starts_at,
    ends_at, timezone, shift_type_id, deleted_at, deleted_by_user_id,
    delete_reason, created_at, updated_at
) VALUES
    ('90000000-0000-0000-0000-000000000001', md5('foundation-day-0')::uuid, 'staff', '70000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 0, 2, '2026-08-02 23:00:00+00', '2026-08-03 07:00:00+00', 'Australia/Melbourne', '80000000-0000-0000-0000-000000000001', NULL, NULL, NULL, '2026-07-06 00:00:00+00', '2026-07-07 00:00:00+00'),
    ('90000000-0000-0000-0000-000000000002', md5('foundation-day-1')::uuid, 'open', NULL, '60000000-0000-0000-0000-000000000002', 1, 3, '2026-08-03 23:00:00+00', '2026-08-04 07:00:00+00', 'Australia/Melbourne', '80000000-0000-0000-0000-000000000001', '2026-07-08 00:00:00+00', '20000000-0000-0000-0000-000000000001', 'old plan', '2026-07-06 00:00:00+00', '2026-07-08 00:00:00+00');
