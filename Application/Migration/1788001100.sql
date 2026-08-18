-- Current resource versions outlive the seven-day event outbox. Keep the latest
-- event ID as opaque publication provenance without retaining its event header.
ALTER TABLE live_resource_versions
    DROP CONSTRAINT live_resource_versions_latest_event_id_fkey;
