-- Durable, additive live-invalidation handoff. Resource payloads are checked
-- by application code and remain versioned JSON so resource additions require
-- no further DDL.
CREATE SEQUENCE live_invalidation_events_sequence_number_seq;
CREATE TABLE live_invalidation_events (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    sequence_number INT DEFAULT nextval('live_invalidation_events_sequence_number_seq') NOT NULL UNIQUE,
    source TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CHECK ((char_length(btrim(source)) > 0) AND (char_length(source) <= 120))
);

CREATE TABLE live_invalidation_event_resources (
    event_id UUID NOT NULL,
    resource_key TEXT NOT NULL,
    resource_payload JSONB NOT NULL,
    PRIMARY KEY (event_id, resource_key),
    FOREIGN KEY (event_id) REFERENCES live_invalidation_events (id) ON DELETE CASCADE,
    CHECK (octet_length(resource_key) <= 2048),
    CHECK (octet_length(resource_payload::TEXT) <= 8192)
);

CREATE TABLE live_resource_versions (
    resource_key TEXT PRIMARY KEY NOT NULL,
    resource_payload JSONB NOT NULL,
    latest_event_id UUID NOT NULL,
    latest_event_sequence INT NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (latest_event_id) REFERENCES live_invalidation_events (id) ON DELETE RESTRICT,
    CHECK (octet_length(resource_key) <= 2048),
    CHECK (octet_length(resource_payload::TEXT) <= 8192)
);

CREATE INDEX idx_live_invalidation_events_created_at ON live_invalidation_events (created_at, id);
CREATE INDEX idx_live_invalidation_event_resources_resource_key ON live_invalidation_event_resources (resource_key);
