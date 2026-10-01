-- Run only against disposable test PostgreSQL. Session-local tables shadow the
-- real names; the operator script itself must still run READ ONLY.
\set ON_ERROR_STOP on
\set venue_id '00000000-0000-0000-0000-000000000001'
\set range_start '2026-11-04'
\set range_end '2026-11-04'
CREATE TEMP TABLE timesheet_entries (
    id uuid, venue_id uuid, operational_date date, starts_at timestamptz,
    ends_at timestamptz, break_starts_at timestamptz, break_ends_at timestamptz,
    deleted_at timestamptz, active_pay_calculation_id uuid
);
CREATE TEMP TABLE timesheet_pay_time_segments (
    id uuid, timesheet_pay_calculation_id uuid, starts_at timestamptz, ends_at timestamptz
);
CREATE TEMP TABLE roster_days (id uuid, venue_id uuid, operational_date date);
CREATE TEMP TABLE roster_slots (
    id uuid, roster_day_id uuid, starts_at timestamptz, ends_at timestamptz, deleted_at timestamptz
);
INSERT INTO timesheet_entries VALUES
 ('00000000-0000-0000-0000-000000000011', :'venue_id', '2026-11-04', '2026-11-04 00:00:00Z', '2026-11-04 01:00:00Z', '2026-11-04 00:01:00.2Z', '2026-11-04 00:02:00.6Z', NULL, '00000000-0000-0000-0000-000000000021'),
 ('00000000-0000-0000-0000-000000000012', :'venue_id', '2026-11-04', '2026-11-04 00:00:00.2Z', '2026-11-04 00:00:01.7Z', NULL, NULL, NULL, NULL),
 ('00000000-0000-0000-0000-000000000013', :'venue_id', '2026-11-04', '2026-11-04 00:00:00.5Z', '2026-11-04 00:00:01.5Z', NULL, NULL, NULL, NULL),
 ('00000000-0000-0000-0000-000000000014', '00000000-0000-0000-0000-000000000002', '2026-11-04', '2026-11-04 00:00:00.2Z', '2026-11-04 00:00:01.7Z', NULL, NULL, NULL, NULL),
 ('00000000-0000-0000-0000-000000000015', :'venue_id', '2026-11-04', '2026-11-04 00:00:00.2Z', '2026-11-04 00:00:01.7Z', NULL, NULL, NOW(), NULL),
 ('00000000-0000-0000-0000-000000000016', :'venue_id', '2026-11-05', '2026-11-05 00:00:00.2Z', '2026-11-05 00:00:01.7Z', NULL, NULL, NULL, NULL);
INSERT INTO timesheet_pay_time_segments VALUES
 ('00000000-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000021', '2026-11-04 00:00:00.4Z', '2026-11-04 00:00:01.6Z'),
 ('00000000-0000-0000-0000-000000000032', '00000000-0000-0000-0000-000000000022', '2026-11-04 00:00:00.4Z', '2026-11-04 00:00:01.6Z');
INSERT INTO roster_days VALUES ('00000000-0000-0000-0000-000000000041', :'venue_id', '2026-11-04');
INSERT INTO roster_slots VALUES ('00000000-0000-0000-0000-000000000051', '00000000-0000-0000-0000-000000000041', '2026-11-04 00:00:00.4Z', '2026-11-04 00:00:01.6Z', NULL);
\ir ../../Application/Deployment/business-duration-audit.sql
