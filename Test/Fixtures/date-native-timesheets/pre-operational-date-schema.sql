DROP SCHEMA IF EXISTS date_native_timesheet_migration_acceptance CASCADE;
CREATE SCHEMA date_native_timesheet_migration_acceptance;
SET LOCAL search_path TO date_native_timesheet_migration_acceptance, public;

CREATE TABLE roster_days (
    id UUID PRIMARY KEY,
    venue_id UUID NOT NULL,
    operational_date DATE NOT NULL
);

CREATE TABLE roster_slots (
    id UUID PRIMARY KEY,
    roster_day_id UUID NOT NULL REFERENCES roster_days (id)
);

CREATE TABLE timesheet_entries (
    id UUID PRIMARY KEY,
    venue_id UUID NOT NULL,
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    timezone TEXT NOT NULL,
    source_roster_slot_id UUID REFERENCES roster_slots (id),
    deleted_at TIMESTAMPTZ
);

INSERT INTO roster_days (id, venue_id, operational_date)
VALUES (
    '10000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    DATE '2026-08-03'
);

INSERT INTO roster_slots (id, roster_day_id)
VALUES (
    '30000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001'
);

-- The roster-derived shift starts at 02:00 on the calendar day following its
-- explicit Operational day. The ad-hoc shift deliberately uses the same local
-- start; conservative backfill retains that local calendar date.
INSERT INTO timesheet_entries (
    id, venue_id, starts_at, ends_at, timezone, source_roster_slot_id, deleted_at
)
VALUES
    (
        '40000000-0000-0000-0000-000000000001',
        '20000000-0000-0000-0000-000000000001',
        TIMESTAMPTZ '2026-08-03 16:00:00+00',
        TIMESTAMPTZ '2026-08-03 19:00:00+00',
        'Australia/Melbourne',
        '30000000-0000-0000-0000-000000000001',
        NULL
    ),
    (
        '40000000-0000-0000-0000-000000000002',
        '20000000-0000-0000-0000-000000000001',
        TIMESTAMPTZ '2026-08-03 16:00:00+00',
        TIMESTAMPTZ '2026-08-03 19:00:00+00',
        'Australia/Melbourne',
        NULL,
        NULL
    );
