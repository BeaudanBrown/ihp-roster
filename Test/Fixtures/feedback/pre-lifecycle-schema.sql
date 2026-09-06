CREATE TYPE feedback_type_enum AS ENUM ('bug', 'suggestion', 'other');

CREATE TABLE users (
    id UUID PRIMARY KEY
);

CREATE TABLE venues (
    id UUID PRIMARY KEY
);

CREATE TABLE user_feedback_items (
    id UUID PRIMARY KEY,
    venue_id UUID NOT NULL REFERENCES venues (id),
    submitted_by_user_id UUID NOT NULL REFERENCES users (id),
    feedback_type feedback_type_enum DEFAULT 'bug' NOT NULL,
    status TEXT DEFAULT 'new' NOT NULL,
    priority TEXT DEFAULT 'normal' NOT NULL,
    content TEXT NOT NULL,
    submitted_path TEXT,
    user_agent TEXT,
    submitted_role TEXT,
    viewport_width INTEGER,
    viewport_height INTEGER,
    device_pixel_ratio DOUBLE PRECISION,
    device_class TEXT,
    display_mode TEXT,
    read_at TIMESTAMP WITH TIME ZONE,
    read_by_user_id UUID,
    support_note TEXT,
    resolved_at TIMESTAMP WITH TIME ZONE,
    resolved_by_user_id UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

INSERT INTO users (id) VALUES
    ('10000000-0000-0000-0000-000000000001'),
    ('10000000-0000-0000-0000-000000000002'),
    ('10000000-0000-0000-0000-000000000003');
INSERT INTO venues (id) VALUES ('20000000-0000-0000-0000-000000000001');
INSERT INTO user_feedback_items
    (id, venue_id, submitted_by_user_id, feedback_type, status, priority, content, submitted_path, support_note, created_at, updated_at)
VALUES
    ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'suggestion', 'done', 'high', E'  \n First retained line  \nmore', '/legacy', 'private operator note', '2025-01-01T00:00:00Z', '2025-02-01T00:00:00Z'),
    ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 'bug', 'new', 'normal', E' \n\t', NULL, NULL, '2025-03-01T00:00:00Z', '2025-03-01T00:00:00Z'),
    ('30000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003', 'other', 'triaged', 'low', E'\f\f\f', NULL, 'retained whitespace case', '2025-04-01T00:00:00Z', '2025-04-01T00:00:00Z');
