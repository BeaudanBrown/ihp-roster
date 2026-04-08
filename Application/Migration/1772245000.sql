CREATE TYPE invitation_delivery_status_enum AS ENUM ('queued', 'sent', 'failed');

ALTER TABLE venue_invitations
    ADD COLUMN delivery_status invitation_delivery_status_enum,
    ADD COLUMN delivery_error TEXT,
    ADD COLUMN delivered_at TIMESTAMP WITH TIME ZONE;

UPDATE venue_invitations
SET
    delivery_status = 'sent',
    delivered_at = COALESCE(updated_at, created_at),
    delivery_error = NULL
WHERE delivery_status IS NULL;

ALTER TABLE venue_invitations
    ALTER COLUMN delivery_status SET DEFAULT 'queued',
    ALTER COLUMN delivery_status SET NOT NULL;
