DROP SCHEMA IF EXISTS roster_template_migration_acceptance CASCADE;
CREATE SCHEMA roster_template_migration_acceptance;
SET LOCAL search_path TO roster_template_migration_acceptance, public;

-- Minimal representative customer schema immediately before roster-template
-- persistence. The migration may add template tables but must not rewrite
-- existing roster-group or roster-week rows.
CREATE TABLE users (
    id UUID PRIMARY KEY
);

CREATE TABLE roster_groups (
    id UUID PRIMARY KEY,
    venue_id UUID NOT NULL
);

CREATE TABLE staff (
    id UUID PRIMARY KEY,
    venue_id UUID NOT NULL
);

CREATE TABLE shift_types (
    id UUID PRIMARY KEY,
    venue_id UUID NOT NULL
);

CREATE TABLE roster_weeks (
    id UUID PRIMARY KEY,
    roster_group_id UUID NOT NULL REFERENCES roster_groups (id),
    is_live BOOLEAN NOT NULL,
    marker TEXT NOT NULL
);

INSERT INTO roster_groups (id, venue_id)
VALUES ('10000000-0000-0000-0000-000000000010', '10000000-0000-0000-0000-000000000020');

INSERT INTO roster_weeks (id, roster_group_id, is_live, marker)
VALUES
    ('10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000010', FALSE, 'legacy-draft-week'),
    ('10000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000010', TRUE, 'legacy-live-week');
